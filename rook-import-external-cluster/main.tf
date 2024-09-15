
locals {
  csi_driver_name_prefix = var.csi_driver_name_prefix == null ? var.operator_namespace : var.csi_driver_name_prefix
  rdb_provisioner        = "${local.csi_driver_name_prefix}.rbd.csi.ceph.com"
  cephfs_provisioner     = "${local.csi_driver_name_prefix}.cephfs.csi.ceph.com"

  cluster_id_rbd    = var.cluster_namespace
  cluster_id_cephfs = var.cluster_namespace

  external_mapping = "{}"
  external_max_mon_id = 2
  external_command_args = ""
}

##########
# Config #
##########
resource "kubernetes_secret_v1" "mon_secret" {
  metadata {
    namespace = var.operator_namespace
    name      = "rook-ceph-mon"
  }

  type = "kubernetes.io/rook"

  data = {
    "cluster-name"  = var.external_cluster.name
    "fsid"          = var.external_cluster.fsid
    "mon-secret"    = var.external_cluster.mon_secret
    "ceph-username" = var.external_cluster.ceph_username
    "ceph-secret"   = var.external_cluster.ceph_secret
  }
}

resource "kubernetes_config_map_v1" "mon_endpoint" {
  metadata {
    namespace = var.operator_namespace
    name      = "rook-ceph-mon-endpoints"
  }

  data = {
    "data" = "ROOK_EXTERNAL_CEPH_MON_DATA"
    "mapping"  = local.external_mapping # ROOK_EXTERNAL_MAPPING
    "maxMonId" = local.external_max_mon_id # ROOK_EXTERNAL_MAX_MON_ID
  }
}

resource "kubernetes_config_map_v1" "external_command" {
  metadata {
    namespace = var.operator_namespace
    name      = "external-cluster-user-command"
  }

  data = {
    "args" = local.external_command_args
  }
}

resource "kubernetes_secret_v1" "csi" {
  for_each = var.csi_secrets

  metadata {
    namespace = var.operator_namespace
    name      = "rook-ceph-csi-${replace(each.key, "_", "-")}"
  }

  type = "kubernetes.io/rook"

  data = {
    "userID"  = each.value.user_id
    "userKey" = each.value.user_key
  }
}

locals {
  csi_secrets_names = {
    for key, value in kubernetes_secret_v1.csi: key => value.metadata[0].name
  }

  has_csi_rbd_secrets    = contains(var.csi_secrets, "rbd_provider") && contains(var.csi_secrets, "rbd_node")
  has_csi_cephfs_secrets = contains(var.csi_secrets, "cephfs_provider") && contains(var.csi_secrets, "cephfs_node")

  csi_storage_class_parameters = {
    for type in concat(
        local.has_csi_rbd_secrets ? ["rbd"] : [],
        local.has_csi_cephfs_secrets ? ["cephfs"] : []
    ): key => {
      "csi.storage.k8s.io/provisioner-secret-namespace"       = var.cluster_namespace
      "csi.storage.k8s.io/controller-expand-secret-namespace" = var.cluster_namespace
      "csi.storage.k8s.io/node-stage-secret-namespace"        = var.cluster_namespace
      "csi.storage.k8s.io/provisioner-secret-name"            = local.csi_secrets_names["${type}_provisioner"]
      "csi.storage.k8s.io/controller-expand-secret-name"      = local.csi_secrets_names["${type}_provisioner"]
      "csi.storage.k8s.io/node-stage-secret-name"             = local.csi_secrets_names["${type}_node"]
    }
  }
}

############
# RBD Pool #
############
resource "kubernetes_manifest" "rados_namespace" {
  for_each = var.rbd_pools

  manifest = yamldecode(templatefile(
    "${path.module}/manifests/CephBlockPoolRadosNamespace.yaml.tftpl",
      {
        RADOS_NAMESPACE = each.value.rados_namespace
        NAMESPACE       = var.cluster_namespace
        RDB_POOL_NAME   = each.value.data_pool_name
      }
    ))
}

locals {
  cluster_rbd_ids = {
    for key, value in kubernetes_manifest.rados_namespace: key => 
      value.object.status.info.clusterID
  }

  rbd_map = merge(var.rbd_pools, var.rbd_topology_pools)
}

resource "kubernetes_storage_class_v1" "rbd" {
  for_each = var.rbd_pools

  metadata {
    name = each.value.storage_class_name
  }

  storage_provisioner    = local.rdb_provisioner
  allow_volume_expansion = true
  reclaim_policy         = "Delete"

  parameters = merge({
    clusterID = local.cluster_rbd_ids[each.key]
    imageFeatures = var.rook_rbd_features
    imageFormat  = "2"
    dataPool     = each.value.data_pool_name
  }, each.value.metadata_pool_name == null ? {} : {
    pool      = each.value.metadata_pool_name
  }, local.csi_storage_class_parameters["rbd"])
  # Add topologies here

  lifecycle {
    precondition {
      condition = local.has_csi_rbd_secrets
      error_message = "var.csi_secrets must contain rbd_provider and rbd_node."
    }

    precondition {
      condition = keys(var.rbd_pools) + keys(var.rbd_topology_pools) == length(local.rbd_map)
      error_message = "Keys on map var.rbd_pools and var.rbd_topology_pools must be different."
    }
  }
}

##########
# CephFS #
##########
resource "kubernetes_manifest" "subvolume_group" {
  for_each = var.cephfs

  manifest = yamldecode(templatefile(
    "${path.module}/manifests/CephFilesystemSubVolumeGroup.yaml.tftpl",
      {
        SUBVOLUME_GROUP = each.value.subvolume_group_name
        NAMESPACE       = var.cluster_namespace
        CEPHFS_FS_NAME  = each.value.cephfs_name
      }
    ))
}

locals {
  cluster_cephfs_ids = {
    for key, value in kubernetes_manifest.subvolume_group: key => 
      value.object.status.info.clusterID
  }
}

resource "kubernetes_storage_class_v1" "rbd" {
  for_each = var.rbd_pools

  metadata {
    name = each.value.storage_class_name
  }

  storage_provisioner    = local.cephfs_provisioner
  allow_volume_expansion = true
  reclaim_policy         = "Delete"

  parameters = merge({
    clusterID = local.cluster_cephfs_ids[each.key]
    fsName    = each.value.fs_name
    pool      = each.value.metadata_pool_name
  }, local.csi_storage_class_parameters["cephfs"])

  lifecycle {
    precondition {
      condition = local.has_csi_cephfs_secrets
      error_message = "var.csi_secrets must contain cephfs_provider and cephfs_node."
    }
  }
}
