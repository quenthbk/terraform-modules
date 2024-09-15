
# Based on the script <https://github.com/rook/rook/blob/v1.15.1/deploy/examples/import-external-cluster.sh>

##################
# Configuration  #
##################
variable "cluster_namespace" {
  description = "External cluster rook namespace"
  type        = string
  default     = "rook-ceph"
}

variable "operator_namespace" {
  description = "Operator rook-ceph namespace"
  type        = string
  default     = "rook-ceph"
}

variable "rook_rbd_features" {
  type    = string
  default = "layering"
}

variable "csi_driver_name_prefix" {
  description = "Default to operator namespace"
  type        = string
  default     = null
}

variable "csi_secrets" {
  description = <<EOF
  Provisioner and node secrets.

  Key map available : 
  rbd_node, rbd_provisioner and / or cephfs_node, cephfs_provisioner
EOF
  type = map(object({
    user_key = string
    user_id  = string
  }))

  validation {
    condition = alltrue([
        for key in keys(var.ceph_config) : contains(
          ["cephfs_node", "cephfs_provisioner", "rbd_node", "rbd_provisioner"],
          key
        )
      ])
    error_message = <<EOF
Only 'cephfs_node', 'cephfs_provisioner', 'rbd_node', and 'rbd_provisioner' are allowed as keys.
    EOF
  }

  validation {
    condition = (
      contains(keys(var.csi_secrets), "cephfs_node") == contains(keys(var.csi_secrets), "cephfs_provisioner")
    ) && (
      contains(keys(var.csi_secrets), "rbd_node") == contains(keys(var.csi_secrets), "rbd_provisioner")
    )

    error_message = <<EOF
  You should specify every cephfs (cephfs_node, cephfs_provisioner) or rbd keys (rbd_cephfs, rbd_provisioner)
EOF
  }
}

####################
# External Cluster #
####################

variable "external_cluster" {
  description = "Information of the external ceph cluster."
  type = object({
    name = string
    fsid = string
    mon_secret    = string
    ceph_username = string
    ceph_secret   = string
  })
}

#############
# BlockPool #
#############

variable "rbd_pools" {
  description = <<EOF
RBD pools to map with a storage class.
If metadata_pool_name is specified, then the RBD pool is considerated as erasure coding.
EOF
  type = map(object({
    metadata_pool_name = optional(string, null)
    data_pool_name     = string
    storage_class_name = string
    rados_namespace    = string
  }))
  default = {}
}

variable "rbd_topology_pools" {
  description = "RBD topologies <https://rook.io/docs/rook/v1.15/CRDs/Cluster/external-cluster/topology-for-external-mode/#ceph-cluster>"
  type = map(object({
    storage_class_name      = string
    rados_namespace         = string
    topology_constrained_pools = list(object({
      pool_name            = string
      failure_domain_value = string
    }))
    failure_domain_label = string
  }))
  default = {}
}

##########
# CephFS #
##########
variable "cephfs" {
  description = <<EOF
  Create Subvolume Groups and storage class for each cephfs.
EOF
  type = map(object({
    metadata_pool_name   = string
    fs_name              = string
    subvolume_group_name = string
    storage_class_name   = string
  }))
}
