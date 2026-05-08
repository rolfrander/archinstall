#!/bin/bash

install=/var/tmp/install.sh
# the install-script downloads itself from this address
src=https://.../local/install.sh
boot=/dev/sda1
swap=/dev/sda2
root=/dev/sda3
efi_platform_size=/sys/firmware/efi/fw_platform_size
SSID=mynetwork

function network() {
    iwctl station list
    iwctl station wlan0 connect $SSID
}

function do_mount() {
    swapon $swap
    mount $root /mnt
    mount --mkdir $boot /mnt/boot

    if [ -d /mnt/var/tmp ]
    then cp $install /mnt$install
    fi
}

function stage_1() {
    mkfs.fat -F 32 $boot
    mkswap $swap
    mkfs.btrfs -f $root

    do_mount

    btrfs subvolume create /mnt/etc
    btrfs subvolume create /mnt/srv
    btrfs subvolume create /mnt/home
    btrfs subvolume create /mnt/usr
    btrfs subvolume create /mnt/var

    pacstrap -K /mnt base linux linux-firmware
    genfstab -U /mnt >> /mnt/etc/fstab
    cp $install /mnt/$install
    arch-chroot /mnt bash $install 2
}

function stage_2() {
    ln -sf /usr/share/zoneinfo/Europe/Oslo /etc/localtime
    hwclock --systohc

    echo enter hostname:
    read hostname
    echo $hostname > /etc/hostname

    # update package database
    pacman -Sy --noconfirm
    # nettverksverktøy
    pacman -S --noconfirm dhclient dialog ethtool iw netctl wpa_supplicant
    # sluttbrukerverktøy
    pacman -S --noconfirm zsh less vim sudo ed
    # bootloader
    pacman -S --noconfirm efibootmgr grub

    # sudoers
    sed -i -e '/wheel/{/NOPASSWD/n;s/^# *//;}' /etc/sudoers

    # locale
    sed -i -e '/^# *(C|en_US|nb_NO|nn_NO).UTF-8/s/^# //' /etc/locale.gen
    
    locale-gen
    echo "LANG=en_US.UTF-8" > /etc/locale.conf

    # GRUB
    sed -i -e '/GRUB_CMDLINE_LINUX_DEFAULT/s/ quiet//;/GRUB_PRELOAD_MODULES/s/ part_msdos//' /etc/default/grub


    grub-install --target=x86_64-efi --efi-directory=/boot --bootloader-id=GRUB
    grub-mkconfig -o /boot/grub/grub.cfg

    # network
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
    
    pacman -S --noconfirm ntp
    systemctl enable ntpd

    pacman -S --noconfirm git openssh man-db

    useradd -m -G wheel -s /usr/bin/zsh $USER
    echo "passord for ny bruker"
    passwd $USER
    echo "reboot nå"
}


if [[ $# -eq 0 ]] 
then 
    curl $src > $install
    echo "run: bash $install 1"
else
    if [ -r $efi_platform_size ]
    then
        platform_size=$(cat $efi_platform_size)
        if [ $platform_size = "64" ]
        then
            case $1 in
            net)
                network
                ;;
            mount)
                do_mount
                ;;
            1)
                stage_1
                ;;
            2)
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
