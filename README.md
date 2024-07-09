# Ubuntu-Custom-Image
Creation of a custom ubuntu image with ccs-cli pre installed onto the ubuntu image

<h2>Cloning, CD, and creating template</h2>

    git clone https://github.com/canonical/packer-maas.git
    cd packer-maas/ubuntu
    nano ubuntu-cloudimg.pkr.hcl

<h2>Delete packer template and insert code from link below</h2>

    https://raw.githubusercontent.com/Quintin-Falk/ubuntu-custom-image-ccs-cli/main/ubuntu-cloudimg.pkr.hcl

To save press ctr+o enter then ctr+x enter

<h2>make image and upload it to maas</h2>

    sudo make custom-cloudimg.tar.gz SERIES=jammy
    sudo maas admin boot-resources create \
        name='custom/ubuntu-tgz' \
        title='Ubuntu Custom TGZ' \
        architecture='amd64/generic' \
        filetype='tgz' \
        content@=custom-cloudimg.tar.gz
    

    
