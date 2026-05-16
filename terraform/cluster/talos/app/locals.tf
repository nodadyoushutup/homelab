locals {
  bootstrap_node   = var.provider_config.talos.bootstrap_node
  talos_endpoint   = var.provider_config.talos.endpoint
  client_endpoints = var.client_endpoints

  hostname_config_patches = {
    k8s_cp_0  = yamlencode({ apiVersion = "v1alpha1", kind = "HostnameConfig", auto = "off", hostname = "k8s-cp-0" })
    k8s_wk_0  = yamlencode({ apiVersion = "v1alpha1", kind = "HostnameConfig", auto = "off", hostname = "k8s-wk-0" })
    k8s_wk_1  = yamlencode({ apiVersion = "v1alpha1", kind = "HostnameConfig", auto = "off", hostname = "k8s-wk-1" })
    k8s_wk_2  = yamlencode({ apiVersion = "v1alpha1", kind = "HostnameConfig", auto = "off", hostname = "k8s-wk-2" })
    k8s_wk_3  = yamlencode({ apiVersion = "v1alpha1", kind = "HostnameConfig", auto = "off", hostname = "k8s-wk-3" })
    k8s_wk_4  = yamlencode({ apiVersion = "v1alpha1", kind = "HostnameConfig", auto = "off", hostname = "k8s-wk-4" })
    k8s_wk_5  = yamlencode({ apiVersion = "v1alpha1", kind = "HostnameConfig", auto = "off", hostname = "k8s-wk-5" })
    k8s_wk_6  = yamlencode({ apiVersion = "v1alpha1", kind = "HostnameConfig", auto = "off", hostname = "k8s-wk-6" })
    k8s_wk_7  = yamlencode({ apiVersion = "v1alpha1", kind = "HostnameConfig", auto = "off", hostname = "k8s-wk-7" })
    k8s_wk_8  = yamlencode({ apiVersion = "v1alpha1", kind = "HostnameConfig", auto = "off", hostname = "k8s-wk-8" })
    k8s_wk_9  = yamlencode({ apiVersion = "v1alpha1", kind = "HostnameConfig", auto = "off", hostname = "k8s-wk-9" })
    k8s_wk_10 = yamlencode({ apiVersion = "v1alpha1", kind = "HostnameConfig", auto = "off", hostname = "k8s-wk-10" })
  }

  client_nodes = [
    var.k8s_cp_0_node,
    var.k8s_wk_0_node,
    var.k8s_wk_1_node,
    var.k8s_wk_2_node,
    var.k8s_wk_3_node,
    var.k8s_wk_4_node,
    var.k8s_wk_5_node,
    var.k8s_wk_6_node,
    var.k8s_wk_7_node,
    var.k8s_wk_8_node,
    var.k8s_wk_9_node,
    var.k8s_wk_10_node,
  ]
}
