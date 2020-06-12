data "local_file" "cluster_bootstrap_state" {
  filename = "${path.module}/cluster_bootstrap_state"
}

data "template_file" "master_userdata_script" {
  template = file("${path.module}/../templates/user_data.sh")

  vars = {
    cloud_provider         = "azure"
    volume_name            = ""
    elasticsearch_data_dir = "/var/lib/elasticsearch"
    elasticsearch_logs_dir = var.elasticsearch_logs_dir
    heap_size              = var.master_heap_size
    es_cluster             = var.es_cluster
    es_environment         = "${var.environment}-${var.es_cluster}"
    security_groups        = ""
    availability_zones     = ""
    master                 = true
    data                   = false
    bootstrap_node         = false
    http_enabled           = false
    masters_count          = var.masters_count
    security_enabled       = var.security_enabled
    monitoring_enabled     = var.monitoring_enabled
    client_user            = ""
    client_pwd             = ""
    xpack_monitoring_host  = var.xpack_monitoring_host
    aws_region             = ""
    azure_resource_group   = ""
    azure_master_vmss_name = ""
  }
}

data "template_file" "bootstrap_userdata_script" {
  template = file("${path.module}/../templates/user_data.sh")

  vars = {
    cloud_provider         = "azure"
    volume_name            = ""
    elasticsearch_data_dir = "/var/lib/elasticsearch"
    elasticsearch_logs_dir = var.elasticsearch_logs_dir
    heap_size              = var.master_heap_size
    es_cluster             = var.es_cluster
    es_environment         = "${var.environment}-${var.es_cluster}"
    security_groups        = ""
    availability_zones     = ""
    master                 = true
    data                   = false
    bootstrap_node         = true
    azure_resource_group   = azurerm_resource_group.elasticsearch.name
    azure_master_vmss_name = azurerm_virtual_machine_scale_set.master-nodes[0].name
    masters_count          = var.masters_count
    security_enabled       = var.security_enabled
    monitoring_enabled     = var.monitoring_enabled
    client_user            = ""
    client_pwd             = ""
    xpack_monitoring_host  = "self"
    aws_region             = ""
  }
}

resource "azurerm_user_assigned_identity" "bootstrap-node-identity" {
  resource_group_name = azurerm_resource_group.elasticsearch.name
  location            = azurerm_resource_group.elasticsearch.location
  name                = "bootstrap-node"
}

resource "azurerm_role_assignment" "bootstrap-node-role-assignment" {
  scope                = data.azurerm_subscription.primary.id
  role_definition_name = "Reader"
  principal_id         = azurerm_user_assigned_identity.bootstrap-node-identity.principal_id
}

resource "azurerm_virtual_machine_scale_set" "master-nodes" {
  count = var.masters_count == 0 ? 0 : 1

  name                = "es-${var.es_cluster}-master-nodes"
  resource_group_name = azurerm_resource_group.elasticsearch.name
  location            = var.azure_location
  sku {
    name     = var.master_instance_type
    tier     = "Standard"
    capacity = var.masters_count
  }
  upgrade_policy_mode = "Manual"
  overprovision       = false

  identity {
    type         = "UserAssigned"
    identity_ids = [azurerm_user_assigned_identity.bootstrap-node-identity.id]
  }

  os_profile {
    computer_name_prefix = "${var.es_cluster}-master"
    admin_username       = "ubuntu"
    admin_password       = random_string.vm-login-password.result
    custom_data          = data.template_file.master_userdata_script.rendered
  }

  network_profile {
    name    = "es-${var.es_cluster}-net-profile"
    primary = true

    ip_configuration {
      name      = "es-${var.es_cluster}-ip-profile"
      primary   = true
      subnet_id = azurerm_subnet.elasticsearch_subnet.id
    }
  }

  storage_profile_image_reference {
    id = data.azurerm_image.elasticsearch.id
  }

  storage_profile_os_disk {
    caching           = "ReadWrite"
    create_option     = "FromImage"
    managed_disk_type = "Standard_LRS"
  }

  storage_profile_data_disk {
    lun               = 0
    caching           = "ReadWrite"
    create_option     = "Empty"
    disk_size_gb      = "10"
    managed_disk_type = "Standard_LRS"
  }

  os_profile_linux_config {
    disable_password_authentication = true
    ssh_keys {
      path     = "/home/ubuntu/.ssh/authorized_keys"
      key_data = file(var.key_path)
    }
  }
}

resource "azurerm_public_ip" "bootstrap" {
  name                = "${var.es_cluster}-bootstrap-node-ip"
  location            = azurerm_resource_group.elasticsearch.location
  resource_group_name = azurerm_resource_group.elasticsearch.name
  allocation_method   = "Dynamic"
}

resource "azurerm_network_interface" "bootstrap-node-nc" {
  name                = "${var.es_cluster}-bootstrap-node-nic"
  location            = azurerm_resource_group.elasticsearch.location
  resource_group_name = azurerm_resource_group.elasticsearch.name

  ip_configuration {
    name                          = "testconfiguration1"
    subnet_id                     = azurerm_subnet.elasticsearch_subnet.id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = azurerm_public_ip.bootstrap.id
  }
}

resource "azurerm_virtual_machine" "bootstrap_node" {
  // Only create if cluster was not bootstrapped before, and not in single-node mode
  count = var.masters_count == 0 && var.datas_count == 0 || data.local_file.cluster_bootstrap_state.content == 1 ? 0 : 1

  name                = "es-${var.es_cluster}-bootstrap-node"
  resource_group_name = azurerm_resource_group.elasticsearch.name
  location            = var.azure_location

  vm_size = var.master_instance_type

  delete_os_disk_on_termination = true

  # "sku" {
  #   name = "${var.master_instance_type}"
  #   tier = "Standard"
  #   capacity = "${var.masters_count}"
  # }
  # overprovision = false

  identity {
    type         = "UserAssigned"
    identity_ids = [azurerm_user_assigned_identity.bootstrap-node-identity.id]
  }

  os_profile {
    computer_name  = "${var.es_cluster}-bootstrap-node"
    admin_username = "ubuntu"
    admin_password = random_string.vm-login-password.result
    custom_data    = data.template_file.bootstrap_userdata_script.rendered
  }

  network_interface_ids = [azurerm_network_interface.bootstrap-node-nc.id]

  # network_profile {
  #   name = "es-${var.es_cluster}-net-profile"
  #   primary = true

  #   ip_configuration {
  #     name = "es-${var.es_cluster}-ip-profile"
  #     primary = true
  #     subnet_id = "${azurerm_subnet.elasticsearch_subnet.id}"
  #   }
  # }

  storage_image_reference {
    id = data.azurerm_image.elasticsearch.id
  }

  storage_os_disk {
    name              = "bootstrap-node-disk"
    caching           = "ReadWrite"
    create_option     = "FromImage"
    managed_disk_type = "Standard_LRS"
  }

  os_profile_linux_config {
    disable_password_authentication = true
    ssh_keys {
      path     = "/home/ubuntu/.ssh/authorized_keys"
      key_data = file(var.key_path)
    }
  }
}

resource "null_resource" "cluster_bootstrap_state" {
  provisioner "local-exec" {
    command = "printf 1 > ${path.module}/cluster_bootstrap_state"
  }
  provisioner "local-exec" {
    when    = destroy
    command = "printf 0 > ${path.module}/cluster_bootstrap_state"
  }

  depends_on = [azurerm_virtual_machine.bootstrap_node]
}

