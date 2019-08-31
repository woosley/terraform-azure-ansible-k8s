provider azurerm {
  subscription_id = "4ebdd33b-3f07-4503-baba-8ad149b81ac1"
  environment     = "china"
}

resource "azurerm_resource_group" "k8s" {
  name     = "${var.admin_user}-k8s-test"
  location = "China North"
}

resource "azurerm_virtual_network" "k8s" {
  name     = "k8s-network"
  address_space  = ["10.0.0.0/16"]
  location = "${azurerm_resource_group.k8s.location}"
  resource_group_name  = "${azurerm_resource_group.k8s.name}"
}

resource "azurerm_subnet" "k8s" {
  name                 = "k8s"
  resource_group_name  = "${azurerm_resource_group.k8s.name}"
  virtual_network_name = "${azurerm_virtual_network.k8s.name}"
  address_prefix       = "10.0.0.0/24"
}

resource "azurerm_network_interface" "k8s" {
  name                = "k8sif-${count.index}"
  count               = 3
  location            = "${azurerm_resource_group.k8s.location}"
  resource_group_name = "${azurerm_resource_group.k8s.name}"

  ip_configuration {
    name                          = "k8sconfiguration1"
    subnet_id                     = "${azurerm_subnet.k8s.id}"
    private_ip_address_allocation = "dynamic"
  }
}

resource "azurerm_managed_disk" "k8s" {
  count                = 3
  name                 = "k8sdisk-${count.index}"
  location             = "${azurerm_resource_group.k8s.location}"
  resource_group_name  = "${azurerm_resource_group.k8s.name}"
  storage_account_type = "Standard_LRS"
  create_option        = "Empty"
  disk_size_gb         = "255"
}

resource "azurerm_virtual_machine" "k8s" {
  name                  = "k8svm-${count.index}"
  count                 = 3
  location              = "${azurerm_resource_group.k8s.location}"
  resource_group_name   = "${azurerm_resource_group.k8s.name}"
  network_interface_ids = ["${azurerm_network_interface.k8s.*.id[count.index]}"]
  vm_size               = "Standard_DS3"

  delete_os_disk_on_termination = true

  delete_data_disks_on_termination = true

  storage_image_reference {
    publisher = "OpenLogic"
    offer     = "CentOS"
    sku       = "7.6"
    version   = "latest"
  }

  storage_os_disk {
    name              = "k8svmosdisk-${count.index}"
    caching           = "ReadWrite"
    create_option     = "FromImage"
    managed_disk_type = "Standard_LRS"
  }

  storage_data_disk {
    name            = "${azurerm_managed_disk.k8s.*.name[count.index]}"
    managed_disk_id = "${azurerm_managed_disk.k8s.*.id[count.index]}"
    create_option   = "Attach"
    lun             = 0
    disk_size_gb    = "${azurerm_managed_disk.k8s.*.disk_size_gb[count.index]}"
  }

  os_profile {
    computer_name  = "k8s-${count.index}"
    admin_username = "${var.admin_user}"
  }

  os_profile_linux_config {
    disable_password_authentication = true

    ssh_keys = {
      path     = "/home/${var.admin_user}/.ssh/authorized_keys"
      key_data = "${file("${path.module}/provisioners/roles/k8s/files/id_rsa.pub")}"
    }
  }

  tags {
    environment = "staging"
  }

}

resource "null_resource" "b" {
  triggers {
    cluster_instance_ids = "${join(",", azurerm_virtual_machine.k8s.*.id)}"
  }

  connection {
    #host = "${azurerm_network_interface.k8s.*.private_ip_address[count.index]}"
    type = "ssh"
    host = "${azurerm_public_ip.bastion.ip_address}"
    private_key = "${file("${path.module}/provisioners/roles/k8s/files/id_rsa")}"
    user = "${var.admin_user}"
    #bastion_host = "${azurerm_public_ip.bastion.ip_address}"
    #bastion_user = "${var.admin_user}"
    #bastion_private_key = "${file("${path.module}/id_rsa")}"
  }
  provisioner "file" {
    source = "./provisioners"
    destination = "/tmp"
  }
  provisioner "remote-exec" {
    inline = [
        "sudo bash /tmp/provisioners/init.sh ${join(" ", azurerm_network_interface.k8s.*.private_ip_address)}"
      ]
  }
}
## bastion
resource "azurerm_network_interface" "bastion" {
  name                = "k8s-bastion"
  location            = "${azurerm_resource_group.k8s.location}"
  resource_group_name = "${azurerm_resource_group.k8s.name}"

  ip_configuration {
    name                          = "bastionsconfiguration1"
    subnet_id                     = "${azurerm_subnet.bastion.id}"
    private_ip_address_allocation = "dynamic"
    public_ip_address_id = "${azurerm_public_ip.bastion.id}"
  }
}

resource "azurerm_subnet" "bastion" {
  name                 = "bastion"
  resource_group_name  = "${azurerm_resource_group.k8s.name}"
  virtual_network_name = "${azurerm_virtual_network.k8s.name}"
  address_prefix       = "10.0.2.0/24"
}

resource "azurerm_public_ip" "bastion" {
  name                         = "bastionpip"
  location            = "${azurerm_resource_group.k8s.location}"
  resource_group_name = "${azurerm_resource_group.k8s.name}"
  public_ip_address_allocation = "static"
}

resource "azurerm_virtual_machine" "bastion" {
  name                  = "bastion"
  location              = "${azurerm_resource_group.k8s.location}"
  resource_group_name   = "${azurerm_resource_group.k8s.name}"
  network_interface_ids = ["${azurerm_network_interface.bastion.id}"]
  vm_size               = "Standard_A1"

  delete_os_disk_on_termination = true

  delete_data_disks_on_termination = true

  storage_image_reference {
    publisher = "OpenLogic"
    offer     = "CentOS"
    sku       = "7.6"
    version   = "latest"
  }

  storage_os_disk {
    name              = "bastion"
    caching           = "ReadWrite"
    create_option     = "FromImage"
    managed_disk_type = "Standard_LRS"
  }


  os_profile {
    computer_name  = "bastion"
    admin_username = "${var.admin_user}"
  }

  os_profile_linux_config {
    disable_password_authentication = true

    ssh_keys = {
      path     = "/home/${var.admin_user}/.ssh/authorized_keys"
      key_data = "${file("${path.module}/provisioners/roles/k8s/files/id_rsa.pub")}"
    }
  }

  tags {
    environment = "staging"
  }
}
