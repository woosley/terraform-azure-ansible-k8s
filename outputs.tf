output "ips" {
  value = "${azurerm_public_ip.bastion.ip_address}"
}
output "k8sips" {
  value = "${azurerm_network_interface.k8s.*.private_ip_address}"
}
