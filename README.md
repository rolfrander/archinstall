# Install-scripts for arch linux

* install.sh assumes the installation disk is formatted and installs a basic setup through several stages. Is designed to download itself from a web-server, addresses and SSID needs to be adjusted.
* Makefile downloads the newest installation-iso, adds a cloud-init partition with ssh-config and can install this to a USB-drive

## configuration of cloud init

The cloud-init is adjusted with local configuration:

* ssh-keys from $HOME/.ssh/authorized_keys and .../*.pub
* SSID and NETWORK_PASS from .env

After booting with the generated USB, you should be able to log in using:

```
ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null root@archiso
```

* `StrictHostKeyChecking=no` means that ssh will not check the host key (it is brand new, so no point in checking)
* `UserKnownHostsFile=/dev/null` means that ssh will not store the checked host-key (it will be regenerated on next boot, so no point in storing it)
