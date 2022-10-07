# The Qubes OS Project, https://www.qubes-os.org/
#
# Copyright (C) 2018 Marek Marczykowski-Górecki <marmarek@invisiblethingslab.com>
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 2 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <https://www.gnu.org/licenses/>.

use base "basetest";
use strict;
use testapi;
use serial_terminal qw(add_serial_console);

sub run {
    my ($self) = @_;

    $self->select_root_console();
    type_string "chroot /mnt/sysimage\n";
    # command echo
    wait_serial("chroot");
    # prompt
    wait_serial("root");
    if (check_var("BACKEND", "qemu")) {
        # include only absolutely necessary files to make the archive small, to be typed
        open EXTRA_TARBALL, "tar cz -C " . testapi::get_required_var('CASEDIR') .
            " extra-files/qubesteststub/__init__.py extra-files/setup.py" .
            "|base64|" or die "failed to create tarball";
        my $tarball = do { local $/; <EXTRA_TARBALL> };
        close(EXTRA_TARBALL);
        assert_script_run("echo '$tarball' | base64 -d | tar xz -C /root");
        assert_script_run("cd /root/extra-files");
        assert_script_run("python3 ./setup.py install");
    }
    assert_script_run("echo '$testapi::password' | passwd --stdin root");
    assert_script_run("sed -i -e 's/^rootpw.*/rootpw --plaintext $testapi::password/' /root/anaconda-ks.cfg");
    script_run("gpasswd -a $testapi::username \$(stat -c %G /dev/$testapi::serialdev)");
    if (check_var('BACKEND', 'qemu')) {
        assert_script_run("systemctl enable serial-getty\@hvc1.service");
    }
    if (get_var('VERSION') =~ /^3/) {
        # disable e820-host, breaks sys-net on OVMF; core2 don't have nice
        # extensions for that...
        # "pci_e820_host": {"default": True}
        my $sed_expr = "s#\\(pci_e820_host.*default.*\\) True#\\1 False#";
        my $core2_path = '/usr/lib64/python2.7/site-packages/qubes/modules/000QubesVm.py';
        type_string "sed -ie '$sed_expr' $core2_path\n";
    }
    type_string "exit\n";
    # command echo
    wait_serial("exit");
    # prompt
    wait_serial("root");
    # when changing here, update release_upgrade.pm too
    my $extra_xen_opts = 'loglvl=all guest_loglvl=all';
    if (check_var("BACKEND", "qemu")) {
        $extra_xen_opts .= ' spec-ctrl=no';
    }
    script_run "sed -i -e 's:console=none:console=vga,com1 $extra_xen_opts:' /mnt/sysimage/boot/grub2/grub.cfg";
    script_run "sed -i -e 's:console=none:console=vga,com1 $extra_xen_opts:' /mnt/sysimage/boot/efi/EFI/qubes/grub.cfg";
    script_run "sed -i -e 's:\\\${xen_rm_opts}::' /mnt/sysimage/boot/efi/EFI/qubes/grub.cfg";
    my $xen_cfg = '/mnt/sysimage/boot/efi/EFI/qubes/xen.cfg';
    if (!script_run("grep console= $xen_cfg")) {
        script_run "sed -i -e 's:console=none:console=vga,com1 $extra_xen_opts:' $xen_cfg";
    } else {
        script_run "sed -i -e 's:^options=:options=console=vga,com1 $extra_xen_opts :' $xen_cfg";
    }
    script_run "sed -i -e 's:console=none:console=vga,com1 $extra_xen_opts:' /mnt/sysimage/etc/default/grub";

    if (get_var('VERSION') eq '4.0') {
        # need to use explicit UUID to override (empty) options from /etc/crypttab,
        # rd.luks.options=discard works only for disks not mentioned in
        # /etc/crypttab; see systemd-cryptsetup-generator(8)
        my $sed_enable_discard = 'sed -i -e \'s:uuid=luks-\([^ ]*\) :\0rd.luks.options=\1=discard :g\'';
        script_run "$sed_enable_discard $xen_cfg";
        script_run "$sed_enable_discard /mnt/sysimage/boot/grub2/grub.cfg";
        script_run "$sed_enable_discard /mnt/sysimage/boot/efi/EFI/qubes/grub.cfg";
        script_run "$sed_enable_discard /mnt/sysimage/etc/default/grub";
    }

    if (check_var("VERSION", "4.1") and !check_var("BACKEND", "qemu")) {
        # force USBVM even with USB keyboard present - do it for R4.1 only -
        # R4.2 should allow it out of the box
        my $ks_addon_path = "/usr/share/anaconda/addons/org_qubes_os_initial_setup/ks/qubes.py";
        my $sed_mock_keyboard_check = 'sed -i -e \'s:^def usb_keyboard_present.*:\0\n    return False:\'';
        script_run "$sed_mock_keyboard_check /mnt/sysimage$ks_addon_path";

        my $policy_path = "/etc/qubes/policy.d/30-openqa.policy";
        script_run "echo 'qubes.InputKeyboard * sys-usb dom0 allow' > /mnt/sysimage$policy_path";
        script_run "echo 'qubes.InputMouse * sys-usb dom0 allow' >> /mnt/sysimage$policy_path";
        script_run "echo 'qubes.InputTablet * sys-usb dom0 allow' >> /mnt/sysimage$policy_path";
    }

    # when changing here, update release_upgrade.pm too
    my $sed_enable_dom0_console_log = 'sed -i -e \'s:quiet:console=hvc0 console=tty0:g\'';
    if (check_var("BACKEND", "qemu")) {
        $sed_enable_dom0_console_log = 'sed -i -e \'s:quiet:console=hvc0 console=tty0 qubes.enable_insecure_pv_passthrough:g\'';
    }
    script_run "$sed_enable_dom0_console_log $xen_cfg";
    script_run "$sed_enable_dom0_console_log /mnt/sysimage/boot/grub2/grub.cfg";
    script_run "$sed_enable_dom0_console_log /mnt/sysimage/boot/efi/EFI/qubes/grub.cfg";
    script_run "$sed_enable_dom0_console_log /mnt/sysimage/etc/default/grub";

    # log resulting bootloader configuration
    script_run "cat /mnt/sysimage/etc/default/grub $xen_cfg";
    script_run "cat /mnt/sysimage/boot/grub2/grub.cfg /mnt/sysimage/boot/efi/EFI/qubes/grub.cfg";

    if (open(my $fh, '<', 'kexec_rollback.txt')) {
        # restore kexec_rollback.txt saved before wiping the disk
        my $rollback = <$fh>;
        close($fh);
        script_run "echo '$rollback' > /mnt/sysimage/boot/kexec_rollback.txt";
    }

    if (open(my $fh, '<', 'kexec_hotp_counter')) {
        # restore kexec_rollback.txt saved before wiping the disk
        my $rollback = <$fh>;
        close($fh);
        script_run "echo '$rollback' > /mnt/sysimage/boot/kexec_hotp_counter";
    }

    # log kickstart file
    script_run "cat /mnt/sysimage/root/anaconda-ks.cfg";

    # improve logging
    script_run "echo 'XENCONSOLED_ARGS=--timestamp=all' >> /mnt/sysimage/etc/sysconfig/xencommons";

    type_string "sync\n";
    select_console('installation');
    #eject_cd;
    #power 'reset';
    assert_and_click 'installer-install-done-reboot';
    reset_consoles();
}

sub test_flags {
    # without anything - rollback to 'lastgood' snapshot if failed
    # 'fatal' - whole test suite is in danger if this fails
    # 'milestone' - after this test succeeds, update 'lastgood'
    # 'important' - if this fails, set the overall state to 'fail'
    return { important => 1 };
}

1;
# vim: set sw=4 et ts=4:
