locals {
  qemu_arch = {
    "amd64" = "x86_64"
    "arm64" = "aarch64"
  }
  uefi_imp = {
    "amd64" = "OVMF"
    "arm64" = "AAVMF"
  }
  qemu_machine = {
    "amd64" = "ubuntu,accel=kvm"
    "arm64" = "virt"
  }
  qemu_cpu = {
    "amd64" = "host"
    "arm64" = "cortex-a57"
  }

  proxy_env = [
    "http_proxy=${var.http_proxy}",
    "https_proxy=${var.https_proxy}",
    "no_proxy=${var.https_proxy}",
  ]
}

source "null" "dependencies" {
  communicator = "none"
}

source "qemu" "cloudimg" {
  boot_wait      = "2s"
  cpus           = 2
  disk_image     = true
  disk_size      = "6G"
  format         = "qcow2"
  headless       = var.headless
  http_directory = var.http_directory
  iso_checksum   = "file:https://cloud-images.ubuntu.com/${var.ubuntu_series}/current/SHA256SUMS"
  iso_url        = "https://cloud-images.ubuntu.com/${var.ubuntu_series}/current/${var.ubuntu_series}-server-cloudimg-${var.architecture}.img"
  memory         = 2048
  qemu_binary    = "qemu-system-${lookup(local.qemu_arch, var.architecture, "")}"
  qemu_img_args {
    create = ["-F", "qcow2"]
  }
  qemuargs = [
    ["-machine", "${lookup(local.qemu_machine, var.architecture, "")}"],
    ["-cpu", "${lookup(local.qemu_cpu, var.architecture, "")}"],
    ["-device", "virtio-gpu-pci"],
    ["-drive", "if=pflash,format=raw,id=ovmf_code,readonly=on,file=/usr/share/${lookup(local.uefi_imp, var.architecture, "")}/${lookup(local.uefi_imp, var.architecture, "")}_CODE_4M.fd"],
    ["-drive", "if=pflash,format=raw,id=ovmf_vars,file=${lookup(local.uefi_imp, var.architecture, "")}_VARS_4M.fd"],
    ["-drive", "file=output-cloudimg/packer-cloudimg,format=qcow2"],
    ["-drive", "file=seeds-cloudimg.iso,format=raw"]
  ]
  shutdown_command       = "sudo -S shutdown -P now"
  ssh_handshake_attempts = 500
  ssh_password           = var.ssh_password
  ssh_timeout            = var.timeout
  ssh_username           = var.ssh_username
  ssh_wait_timeout       = var.timeout
  use_backing_file       = true
}

build {
  name    = "cloudimg.deps"
  sources = ["source.null.dependencies"]

  provisioner "shell-local" {
    inline = [
      "cp /usr/share/${lookup(local.uefi_imp, var.architecture, "")}/${lookup(local.uefi_imp, var.architecture, "")}_VARS_4M.fd ${lookup(local.uefi_imp, var.architecture, "")}_VARS_4M.fd",
      "cloud-localds seeds-cloudimg.iso user-data-cloudimg meta-data"
    ]
    inline_shebang = "/bin/bash -e"
  }
}

build {
  name    = "cloudimg.image"
  sources = ["source.qemu.cloudimg"]
  provisioner "shell" {
    inline = [
      "export CUDA=12-5",
      "export CUDA_DRIVER=550",
      "export CUDA_DRIVER_FABRICMANAGER=550",
      "export CUDNN=8.9.7.29-1+cuda12.2",
      "sudo DEBIAN_FRONTEND=noninteractive apt install curl -y",
      "sudo DEBIAN_FRONTEND=noninteractive apt install dpkg -y",
      ". /etc/os-release",
      "sudo systemctl set-default multi-user.target",
      "arch=x86_64",
      "distro=ubuntu$(echo $VERSION_ID | tr -d .)",
      "curl -s -O https://developer.download.nvidia.com/compute/cuda/repos/$distro/$arch/cuda-keyring_1.1-1_all.deb",
      "sudo dpkg -i cuda-keyring_1.1-1_all.deb",
      "sudo DEBIAN_FRONTEND=noninteractive apt-get update -y",
      "sudo DEBIAN_FRONTEND=noninteractive apt-get install -y linux-headers-$(uname -r)",
      "sudo DEBIAN_FRONTEND=noninteractive apt-get install cuda-toolkit-$CUDA_DRIVER -y && sudo apt-mark hold cuda-toolkit-$CUDA_DRIVER",
      "sudo DEBIAN_FRONTEND=noninteractive apt-get install cuda-drivers-fabricmanager-$CUDA_DRIVER -y && sudo apt-mark hold cuda-drivers-fabricmanager-$CUDA_DRIVER",
      "sudo systemctl enable nvidia-fabricmanager",
      "sudo DEBIAN_FRONTEND=noninteractive apt-get install cuda-drivers-$CUDA_DRIVER -y && sudo apt-mark hold cuda-drivers-$CUDA_DRIVER",
      "sudo DEBIAN_FRONTEND=noninteractive apt-get install libcudnn8=$CUDNN -y && sudo apt-mark hold libcudnn8",
      "sudo tee /etc/profile.d/cirrascale-cuda.sh > /dev/null << 'EOF'",
      "echo 'export PATH=/usr/local/cuda/bin:$PATH' >> /home/ubuntu/.bashrc",
      "echo 'export LD_LIBRARY_PATH=/usr/local/cuda/lib64:$LD_LIBRARY_PATH' >> /home/ubuntu/.bashrc",
      "EOF",
      "sudo tee -a /etc/apt/apt.conf.d/50unattended-upgrades <<EOF",
      "Unattended-Upgrade::Package-Blacklist {'nvidia';'cuda';'libnvidia';'libcudnn';};",
      "EOF",
      "sudo DEBIAN_FRONTEND=noninteractive apt-get install python3-pip -y",
      "sudo pip3 install git+https://github.com/cirrascalecloudservices/ccs-cli --force-reinstall",
]
  }


  provisioner "shell" {
    environment_vars = concat(local.proxy_env, ["DEBIAN_FRONTEND=noninteractive"])
    scripts          = ["${path.root}/scripts/cloudimg/setup-boot.sh"]
  }


  provisioner "shell" {
    environment_vars  = concat(local.proxy_env, ["DEBIAN_FRONTEND=noninteractive"])
    expect_disconnect = true
    scripts           = [var.customize_script]
  }

  provisioner "shell" {
    environment_vars = [
      "CLOUDIMG_CUSTOM_KERNEL=${var.kernel}",
      "DEBIAN_FRONTEND=noninteractive"
    ]
    scripts = ["${path.root}/scripts/cloudimg/install-custom-kernel.sh"]
  }

  provisioner "file" {
    destination = "/tmp/"
    sources     = ["${path.root}/scripts/cloudimg/curtin-hooks"]
  }

  provisioner "shell" {
    environment_vars = ["CLOUDIMG_CUSTOM_KERNEL=${var.kernel}"]
    scripts          = ["${path.root}/scripts/cloudimg/setup-curtin.sh"]
  }

  provisioner "shell" {
    environment_vars = ["DEBIAN_FRONTEND=noninteractive"]
    scripts          = ["${path.root}/scripts/cloudimg/cleanup.sh"]
  }

  post-processor "shell-local" {
    inline = [
      "IMG_FMT=qcow2",
      "SOURCE=cloudimg",
      "ROOT_PARTITION=1",
      "DETECT_BLS_BOOT=1",
      "OUTPUT=${var.filename}",
      "source ../scripts/fuse-nbd",
      "source ../scripts/fuse-tar-root"
    ]
    inline_shebang = "/bin/bash -e"
  }
}
