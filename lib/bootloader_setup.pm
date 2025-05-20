# Copyright © 2016-2017 SUSE LLC
#
# Copying and distribution of this file, with or without modification,
# are permitted in any medium without royalty provided the copyright
# notice and this notice are preserved.  This file is offered as-is,
# without any warranty.

package bootloader_setup;

use base Exporter;
use Exporter;

use strict;

use testapi;

our @EXPORT = qw(
  pre_bootmenu_setup
  stop_grub_timeout
  tianocore_enter_menu
  tianocore_select_bootloader
  heads_boot_usb
  heads_boot_default
);

# choose boot device according to test variables; useful for booting from cdrom
# the second time, when the disk already contains some system
sub pre_bootmenu_setup {
    if (!get_var('UEFI') and check_var('BOOT_MENU', '1')) {
        assert_screen "boot-menu", 5;
        send_key('esc');
        assert_screen "boot-menu-select", 4;
        if (get_var("USBBOOT")) {
            send_key(3 + get_var("NUMDISKS"));
        } else {
            send_key(2 + get_var("NUMDISKS"));
        }
    }

    if (get_var("BOOT_HDD_IMAGE")) {
        assert_screen "grub2", 15;    # Use the same bootloader needle as in grub-test
        send_key "ret";               # boot from hd
        return 3;
    }
    return 0;
}

# prevent grub2 timeout; 'esc' would be cleaner, but grub2-efi falls to the menu then
# 'up' also works in textmode and UEFI menues.
sub stop_grub_timeout {
    send_key 'up';
}

sub tianocore_enter_menu {
    # press F2 and be quick about it
    send_key_until_needlematch('tianocore-mainmenu', 'f2', 15, 1);
}

sub tianocore_select_bootloader {
    tianocore_enter_menu;
    send_key_until_needlematch('tianocore-bootmanager', 'down', 5, 5);
    send_key 'ret';
}

sub heads_boot_usb {
    # FIXME: workaround for broken HDMI after cold boot
    # https://github.com/linuxboot/heads/issues/1557
    if (!check_screen(['heads-menu', 'heads-no-boot', 'heads-no-os', 'heads-hotp-fail-screen'], timeout => 30)) {
        send_key("ctrl-alt-delete");
        sleep(5);
    }
    assert_screen(['heads-menu', 'heads-no-boot', 'heads-no-os', 'heads-hotp-fail-screen'], timeout => 45);
    my $usb_boot_selected = 0;
    if (match_has_tag('heads-no-os')) {
        # Select "Boot from USB"
        send_key 'down';
        send_key 'ret';
        $usb_boot_selected = 1;
    } elsif (match_has_tag('heads-no-boot')) {
        send_key 'right';
        send_key 'ret';
        assert_screen('heads-menu');
    } elsif (match_has_tag('heads-hotp-fail-screen')) {
        # choose "Ignore error and continue to main menu"
        send_key 'down';
        send_key 'ret';
    }
    if (!$usb_boot_selected) {
        # select options
        send_key 'down';
        send_key 'down';
        send_key 'ret';
        assert_screen('heads-options');
        # select boot menu
        send_key 'ret';
        sleep(10);
        assert_screen('heads-boot-options');
        # select USB boot
        send_key 'down';
        send_key 'ret';
    }
    assert_screen(['heads-usb-boot-options', 'heads-usb-boot-list', 'heads-usb-boot-disk-list']);
    if (match_has_tag('heads-usb-boot-disk-list')) {
        my $tries = 7;
        while ($tries > 0 and !check_screen("heads-usb-boot-disk-entry", timeout => 5)) {
            wait_screen_change {
                send_key 'down';
            };
            $tries--;
        }
        send_key 'ret';
        assert_screen(['heads-usb-boot-options', 'heads-usb-boot-list']);
    }
    my $tries = 7;
    # misleadingly named needle heads-usb-boot-options is the default installer entry
    my $boot_option_needle = "heads-usb-boot-options";
    $boot_option_needle = "heads-usb-boot-oem" if check_var("INSTALL_OEM_STARTUP", "1");
    # scroll to the right option
    while ($tries > 0 and !check_screen($boot_option_needle)) {
        wait_screen_change {
            send_key 'down';
        };
        $tries--;
    }
    # boot the default, ISO post-processing already disabled media check
    assert_screen($boot_option_needle);
    send_key 'ret';
}

sub heads_generate_hotp {
    my (%args) = @_;
    $args{reset_tpm} //= 0;

    # regerenerate HOTP secret
    send_key 'down';
    send_key 'down';
    send_key 'ret';
    assert_screen('heads-options');
    send_key 'down';
    send_key 'ret';
    assert_screen('heads-hotp-options');
    if ($args{reset_tpm}) {
        send_key 'down';
        send_key 'ret';
        assert_screen('heads-tpm-reset-confirm');
        send_key 'ret';
        assert_screen('heads-new-tpm-owner-prompt');
        type_string '12345678';
        send_key 'ret';
        type_string '12345678';
        send_key 'ret';
        if (check_screen('heads-tpm-owner-prompt', 10)) {
            type_string '12345678';
            send_key 'ret';
        }
        # Would you like to update the checksums and sign all of the files in /boot?
        if (check_screen('heads-tpm-reset-success', 10)) {
            send_key 'ret';
            # Please confirm that your GPG card is inserted [Y/n]: 
            assert_screen('heads-gpg-card-prompt');
            send_key 'ret';
            sleep(2);
            # PIN:
            assert_screen('heads-gpg-card-pin-prompt');
            type_string '123456';
            send_key 'ret';
        }
    } else {
        send_key 'ret';
    }
    assert_screen(['heads-generate-hotp-confirm', 'heads-scan-qr', 'heads-tpm-owner-prompt']);
    if (match_has_tag('heads-tpm-owner-prompt')) {
        type_string '12345678';
        send_key 'ret';
        assert_screen(['heads-generate-hotp-confirm', 'heads-scan-qr']);
    }
    if (match_has_tag('heads-generate-hotp-confirm')) {
        send_key 'ret';
        assert_screen('heads-scan-qr');
    }
    send_key 'ret';
    if (check_screen('heads-admin-pin-prompt', 15)) {
        if (!match_has_tag('heads-admin-pin-default-detected')) {
            type_string '12345678';
        }
        send_key 'ret';
        # this screen isn't present in newer Heads builds anymore
        if (check_screen('heads-nitrokey-init-success', 30)) {
            send_key 'ret';
        }
        if (check_var("HEADS_DISK_UNLOCK", "1") and check_screen('heads-disk-recovery-key-prompt', 15)) {
            # WARNING: TPM sealed Disk Unlock Key secret needs to be resealed ...
            # Resealing TPM LUKS Unlock Key ...
            # Enter Disk Recovery Key/passphrase:
            assert_screen('heads-disk-recovery-key-prompt');
            send_key 'lukspass';
            send_key 'ret';
            assert_screen("heads-disk-unlock-key-prompt");
            type_string 'unlockpass';
            send_key 'ret';
            type_string 'unlockpass';
            send_key 'ret';
            # let it remove/add slot and scroll a bit to hide old pin prompts
            sleep(10);
        }
    }
    assert_screen('heads-menu');
    if (match_has_tag('heads-menu-hotp-fail')) {
        # click refresh
        send_key 'down';
        send_key 'ret';
        sleep 5;
        assert_screen('heads-menu');
    }
    die "HOTP verification failed" if match_has_tag('heads-menu-hotp-fail');
}

sub heads_boot_default {
    # FIXME: workaround for broken HDMI after cold boot
    if (!check_screen(['heads-menu', 'heads-hotp-fail-screen'], timeout => 120)) {
        send_key("ctrl-alt-delete");
        sleep(3);
    }

    assert_screen(['heads-menu', 'heads-hotp-fail-screen'], 120);
    if (match_has_tag('heads-menu-hotp-fail')) {
        if (check_var("MACHINE", "hw5")) {
            heads_generate_hotp(reset_tpm => 1);
        } else {
            heads_generate_hotp;
        }
    } elsif (match_has_tag('heads-hotp-fail-screen')) {
        # choose "Ignore error and continue to main menu"
        send_key 'down';
        send_key 'ret';
        wait_still_screen;
        if (check_var("MACHINE", "hw5")) {
            heads_generate_hotp(reset_tpm => 1);
        } else {
            heads_generate_hotp;
        }
    }
    # Default boot
    send_key 'ret';
    if (check_screen(['heads-no-hashes', 'heads-hash-mismatch'], 10)) {
        send_key 'ret';
        if (check_screen("heads-hash-mismatch-list", 10)) {
            send_key 'q';
        }
        assert_screen(['heads-update-hashes-prompt', 'heads-gpg-card-prompt']);
        if (match_has_tag('heads-update-hashes-prompt')) {
            send_key 'ret';
            assert_screen('heads-gpg-card-prompt');
        }
        send_key 'ret';
        assert_screen(['heads-gpg-card-pin-prompt', 'heads-tpm-owner-prompt']);
        if (match_has_tag('heads-tpm-owner-prompt')) {
            # kexec_rollback.txt does not exist; creating new TPM counter
            type_string '12345678';
            send_key 'ret';
            assert_screen(['heads-gpg-card-pin-prompt', 'heads-tpm-out-of-resources', 'heads-fail-hashes-sign']);
            if (match_has_tag('heads-tpm-out-of-resources') or match_has_tag('heads-fail-hashes-sign')) {
                # need reset TPM to cleanup old counters
                send_key 'ret';
                assert_screen('heads-menu');
                heads_generate_hotp(reset_tpm => 1);
                # then try again
                heads_boot_default();
                return;
            }
        }
        type_string '123456';
        send_key 'ret';
    }
    if (check_screen('heads-menu', 10)) {
        send_key 'ret';
    }
    if (check_screen(['heads-no-default-set', 'heads-boot-list-changed'], 10)) {
        send_key 'ret';
        assert_screen('heads-boot-menu-list');
        send_key 'ret';
        assert_screen(['heads-confirm-default-select', 'heads-confirm-default-selected']);
        if (!match_has_tag('heads-confirm-default-selected')) {
            # make default, not just one time boot
            send_key 'down';
        }
        send_key 'ret';
        if (check_var("HEADS_DISK_UNLOCK", "1")) {
            # Do you wish to add a disk encryption to the TPM [y/N]?
            assert_screen('heads-disk-key-tpm-prompt');
            send_key 'y';
            # (only on update, not fresh install)
            # Do you want to reuse configured Encrypted LVM groups/ Block devices? [Y/n]:
            if (check_screen("heads-disk-key-config-reuse", 15)) {
                send_key 'y';
            }
            assert_screen("heads-disk-recovery-key-prompt");
            type_string 'lukspass';
            send_key 'ret';
            assert_screen("heads-disk-unlock-key-prompt");
            type_string 'unlockpass';
            send_key 'ret';
            type_string 'unlockpass';
            send_key 'ret';
            # let it remove/add slot and scroll a bit to hide old pin prompts
            sleep(15);
        } else {
            # Saving a default will modify the disk. Proceed? (Y/n)
            if (check_screen('heads-confirm-modify-disk', 15)) {
                send_key 'ret';
            }
            # Do you wish to add a disk encryption to the TPM [y/N]?
            assert_screen('heads-disk-key-tpm-prompt');
            send_key 'ret';
            # let it remove/add slot and scroll a bit to hide old pin prompts
            sleep(10);
        }
        # FIXME: this and the next one matches prompt from earlier (still at the top of the screen)
        assert_screen('heads-gpg-card-prompt');
        send_key 'ret';
        sleep(2);
        assert_screen('heads-gpg-card-pin-prompt');
        type_string '123456';
        send_key 'ret';
    }
    if (check_screen('heads-menu', 30)) {
        # depending on Heads version, generating /boot hashes is followed by reboot
        send_key 'ret';
    }
    if (check_var("HEADS_DISK_UNLOCK", "1")) {
        # Enter LUKS Disk Unlock Key passphrase (blank to abort):
        assert_screen('heads-disk-unlock-prompt');
        type_string 'unlockpass';
        send_key 'ret';
    }
}
