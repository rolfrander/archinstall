#!/bin/bash

install=/var/tmp/install.sh
# the install-script downloads itself from this address
src=https://.../local/install.sh
# set username
localuser=username
# network
SSID=mynetwork

# these are all assumptions
boot=/dev/sda1
swap=/dev/sda2
root=/dev/sda3

efi_platform_size=/sys/firmware/efi/fw_platform_size
netconfdir=/etc/systemd/network

wifi_connect() {
    iwctl station list
    iwctl station wlan0 connect $SSID
}

do_mount() {
    swapon $swap
    mount $root /mnt
    mount --mkdir $boot /mnt/boot

    if [ -d /mnt/var/tmp ]
    then cp $install /mnt$install
    fi
}

root_btrfs() {
    mkfs.fat -F 32 $boot
    mkswap $swap
    mkfs.btrfs -f $root

    do_mount

    btrfs subvolume create /mnt/etc
    btrfs subvolume create /mnt/srv
    btrfs subvolume create /mnt/home
    btrfs subvolume create /mnt/usr
    btrfs subvolume create /mnt/var
}

root_ext4() {
    mkfs.fat -F 32 $boot
    mkswap $swap
    mkfs.ext4 $root

    do_mount
}

stage_1() {
    pacstrap -K /mnt base linux linux-firmware
    genfstab -U /mnt >> /mnt/etc/fstab
    cp $install /mnt/$install
    #arch-chroot /mnt bash $install 2
    echo "stage 1 is done, ready for stage 2:"
    echo " - chroot with: arch-chroot /mnt"
    echo " - $install 2"
    echo " - setup wired network (using systemd-networkd) with:"
    echo "   $install add_vlan device vlan-id ip [vlan-id ip]*"
    echo "   $install add_static device ip"
    echo "   $install setup_wired"
    echo "   check files in /etc/systemd/network"
    echo " - or setup wireless (using netctl) with:"
    echo "   $install setup_wireless"
    echo "   check files in /etc/netctl"
}

stage_2() {
    ln -sf /usr/share/zoneinfo/Europe/Oslo /etc/localtime
    hwclock --systohc

    # update package database
    pacman -Sy --noconfirm
    # sluttbrukerverktøy
    pacman -S --noconfirm zsh less vim sudo ed bat eza fzf
    # docker
    pacman -S --noconfirm docker docker-compose docker-buildx
    # bootloader
    pacman -S --noconfirm efibootmgr grub

    # sudoers
    sed -i -e '/wheel/{/NOPASSWD/n;s/^# *//;}' /etc/sudoers

    # locale
    sed -i -e '/^# *(C|en_US|nb_NO|nn_NO).UTF-8/s/^# *//' /etc/locale.gen

    locale-gen
    echo "LANG=en_US.UTF-8" > /etc/locale.conf

    # GRUB
    sed -i -e '/GRUB_CMDLINE_LINUX_DEFAULT/s/ quiet//;/GRUB_PRELOAD_MODULES/s/ part_msdos//' /etc/default/grub


    grub-install --target=x86_64-efi --efi-directory=/boot --bootloader-id=GRUB
    grub-mkconfig -o /boot/grub/grub.cfg

    pacman -S --noconfirm ntp
    systemctl enable ntpd

    pacman -S --noconfirm git openssh man-db

    useradd -m -G wheel -s /usr/bin/zsh $localuser
    echo "passord for ny bruker"
    passwd $localuser
    echo "reboot nå"
}

generate_networkd_network() {
    local ifc=$1
    local ip=$2
    cat <<EOF
[Match]
Name=$ifc

[Network]
Address=$ip/24
Gateway=192.168.2.1
DNS=192.168.2.1
Domains=folkestad-naess.name
EOF
}

setup_networkd_vlan() {
    # usage:
    # setup_networkd_vlan <device> <vlan-id> <ip> [<vlan-id> <ip>]*
    local ifc=$1
    shift
    cat > $netconfdir/10-$ifc.network <<EOF
[Match]
Name=$ifc

[Network]
EOF
    while [ ! -z "$1" ]
    do
      local vlan=$1
      shift
      local ip=$1
      shift
      echo "VLAN=$ifc.$vlan" >> $netconfdir/10-$ifc.network
      cat > $netconfdir/20-$ifc-vlan$vlan.netdev <<EOF
[NetDev]
Name=$ifc.$vlan
Kind=vlan

[VLAN]
Id=$vlan
EOF
      generate_networkd_network "$ifc.$vlan" $ip > $netconfdir/30-$ifc-vlan$vlan.network
    done
}

setup_networkd_ifc() {
    # usage:
    # setup_networkd_ifc <device> <ip>
    ifc=$1
    ip=$2
    generate_networkd_network $ifc $ip > $netconfdir/10-$ifc.network
}

wired_static() {
    # assumes config files in /etc/systemd/network
    # netctl is unstable with wired connections, systemd-networkd seems to work, but is a bit more involved config
    systemctl enable systemd-networkd
    systemctl enable systemd-resolved
    echo $hostname > /etc/hostname
    hostnamectl set-hostname $hostname
    ln -sf /run/systemd/resolve/stub-resolv.conf /etc/resolv.conf
}

wireless_dhcp() {
    # network
    pacman -S --noconfirm dhclient dialog ethtool iw netctl wpa_supplicant
    echo $hostname > /etc/hostname
    cat > /etc/netctl/$SSID <<EOF
Description='A simple WPA encrypted wireless connection'
Interface=wlp4s0
Connection=wireless
Security=wpa
IP=dhcp
IP6=no
ESSID='$SSID'
Key='$PASS'
EOF

    cat > /etc/netctl/hooks/dhcp <<EOF
#!/bin/sh
DHCPClient='dhclient'
EOF

    chmod +x /etc/netctl/hooks/dhcp
    
}


if [[ $# -eq 0 ]] 
then 
    curl $src > $install
    echo "run: bash $install format_btrfs"
    echo "or: bash $install format_ext4"
else
    if [ -r $efi_platform_size ]
    then
        platform_size=$(cat $efi_platform_size)
        if [ $platform_size = "64" ]
        then
            mode=$1
            shift
            case $mode in
            wifi)
                wifi_connect
                ;;
            mount)
                do_mount
                ;;
            format_btrfs)
                root_btrfs
                ;;
            format_ext4)
                root_ext4)
                ;;
            1)
                # stage 1 is in the USB-root
                stage_1
                ;;
            setup_wireless)
                # part of stage 2, after chroot
                wireless_dhcp
                ;;
            add_vlan)
                setup_networkd_wlan $*
                ;;
            add_static)
                setup_networkd_ifc $*
                ;;
            setup_wired)
                # part of stage 2, after chroot, assumes add_* is done
                wired_static
                ;;

            2)
                # stage 2 is after chroot to /mnt
                stage_2
                ;;
            esac
        else
            echo "unexpected platform size: $platform_size"
        fi
    else
        echo "not booted in EFI-mode"
    fi
fi
