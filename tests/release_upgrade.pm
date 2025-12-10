# The Qubes OS Project, https://www.qubes-os.org/
#
# Copyright (C) 2020 Marek Marczykowski-Górecki <marmarek@invisiblethingslab.com>
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

use base "installedtest";
use strict;
use testapi;
use networking;
use utils qw(us_colemak colemak_us);

sub upgrade_40_to_41_before_reboot {
    assert_script_run("script -a -e -c 'sudo qubes-dist-upgrade --assumeyes --double-metadata-size' release-upgrade.log", timeout => 60);
    assert_script_run("script -a -e -c 'sudo qubes-dist-upgrade --assumeyes --update --max-concurrency=1' release-upgrade.log", timeout => 7200);
    assert_script_run("script -a -e -c 'sudo qubes-dist-upgrade --assumeyes --template-standalone-upgrade' release-upgrade.log", timeout => 7200);
    assert_script_run("script -a -e -c 'sudo qubes-dist-upgrade --assumeyes --release-upgrade' release-upgrade.log", timeout => 300);
    assert_script_run("script -a -e -c 'sudo qubes-dist-upgrade --assumeyes --dist-upgrade' release-upgrade.log", timeout => 7200);
    sleep(1);
    send_key('ctrl-c');

    # reset keyboard layout (but still test if after reboot)
    if (check_var('KEYBOARD_LAYOUT', 'us-colemak')) {
        x11_start_program(us_colemak('setxkbmap us'), valid => 0);
    } elsif (get_var('LOCALE')) {
        x11_start_program('setxkbmap us', valid => 0);
    }
    sleep(1);
    send_key('ctrl-c');

    assert_script_run("script -a -e -c 'sudo qubes-dist-upgrade --assumeyes --setup-efi-grub' release-upgrade.log", timeout => 3600);

    if (0) {
        # manually "do" assert_script_run, to support interaction
        type_string("script -a -e -c 'sudo qubes-dist-upgrade --assumeyes --convert-luks' release-upgrade.log");
        type_string("; echo marker-\$?- > /dev/$testapi::serialdev\n");
        # up to 2 LUKS partitions (rootfs, swap), then wait for the thing to end
        my $res;
        for my $iter (1 .. 3) {
            $res = wait_serial(qr/marker-\d+-/, timeout => 10);
            last if $res;
            type_string("lukspass");
            send_key('ret');
        }
        die "'qubes-dist-upgrade --assumeyes --convert-luks' timed out" if (!defined $res);
        die "'qubes-dist-upgrade --assumeyes --convert-luks' failed" if (($res =~ /marker-(\d+)-/)[0] != 0);
    }

}

sub upgrade_40_to_41_after_reboot {
    assert_script_run("script -a -e -c 'sudo qubes-dist-upgrade --assumeyes --resync-appmenus-features' release-upgrade-post-reboot.log", timeout => 3600);
}

sub adjust_xen_cmdline {
    my $extra_xen_opts = 'loglvl=all guest_loglvl=all';
    my $serial_console = "com1";
    if (check_var("BACKEND", "qemu")) {
        $extra_xen_opts .= ' spec-ctrl=no';
    }
    if (check_var("MACHINE", "hw7")) {
# not really AMT, but LPSS on PCI bus 0
        $extra_xen_opts .= ' com1=115200,8n1,amt';
    } elsif (check_var("MACHINE", "hw1")) {
        $extra_xen_opts .= ' com1=115200,8n1,pci,msi,04:00.0';
    } elsif (check_var("MACHINE", "hw2")) {
        $extra_xen_opts .= ' com1=115200,8n1';
    } elsif (check_var("MACHINE", "hw8")) {
        $extra_xen_opts .= ' dbgp=xhci@pci00:14.0,share=yes';
        $serial_console = "xhci";
    }
    if (!script_run("grep 'GRUB_CMDLINE_XEN_DEFAULT.*console=' /etc/default/grub")) {
        script_run "sudo sed -i -e 's/console=none/console=vga,$serial_console $extra_xen_opts/' /etc/default/grub";
    } else {
        script_run "sudo sed -i -e 's/GRUB_CMDLINE_XEN_DEFAULT=\"/\\0console=vga,$serial_console $extra_xen_opts /' /etc/default/grub";
    }
    if (!script_run("grep 'multiboot.*console=' /boot/efi/EFI/qubes/grub.cfg")) {
        script_run "sudo sed -i -e 's/console=none/console=vga,$serial_console $extra_xen_opts/' /boot/efi/EFI/qubes/grub.cfg";
    } else {
        script_run "sudo sed -i -e 's/multiboot.*/\\0 console=vga,$serial_console $extra_xen_opts/' /boot/efi/EFI/qubes/grub.cfg";
    }
    my $sed_enable_dom0_console_log = 'sed -i -e \'s:quiet:console=hvc0 console=tty0:g\'';
    if (check_var("BACKEND", "qemu")) {
        $sed_enable_dom0_console_log = 'sed -i -e \'s:quiet:console=hvc0 console=tty0 qubes.enable_insecure_pv_passthrough:g\'';
    }
    script_run "sudo $sed_enable_dom0_console_log /boot/efi/EFI/qubes/grub.cfg";
    script_run "sudo $sed_enable_dom0_console_log /etc/default/grub";
    set_var('UEFI_DIRECT', '');
# upload_logs doesn't work here, until reboot
    script_run "sudo cat /etc/default/grub";
    save_screenshot;
    script_run "sudo grep -C 5 vmlinuz /boot/efi/EFI/qubes/grub.cfg";
    save_screenshot;
}

sub upgrade_41_to_42_before_reboot {
    assert_script_run("script -a -e -c 'sudo qubes-dist-upgrade --assumeyes --update --max-concurrency=1' release-upgrade.log", timeout => 7200);
    assert_script_run("script -a -e -c 'sudo qubes-dist-upgrade --assumeyes --release-upgrade' release-upgrade.log", timeout => 600);
    assert_script_run("script -a -e -c 'sudo qubes-dist-upgrade --assumeyes --dist-upgrade' release-upgrade.log", timeout => 7200);
    sleep(1);
    send_key('ctrl-c');

    # reset keyboard layout (but still test if after reboot)
    if (check_var('KEYBOARD_LAYOUT', 'us-colemak')) {
        x11_start_program(us_colemak('setxkbmap us'), valid => 0);
    } elsif (get_var('LOCALE')) {
        x11_start_program('setxkbmap us', valid => 0);
    }
    sleep(1);
}

sub upgrade_41_to_42_after_reboot {
    my ($self) = @_;

    assert_script_run("script -a -e -c 'sudo qubes-dist-upgrade --assumeyes --template-standalone-upgrade' release-upgrade.log", timeout => 8000);
    $self->maybe_unlock_screen;
    assert_script_run("script -a -e -c 'sudo qubes-dist-upgrade --assumeyes --finalize' release-upgrade-post-reboot.log", timeout => 7200);
    $self->maybe_unlock_screen;
    assert_script_run("script -a -e -c 'sudo qubes-dist-upgrade --assumeyes --convert-policy' release-upgrade-post-reboot.log", timeout => 600);
    $self->maybe_unlock_screen;
}

sub upgrade_42_to_43_before_reboot {
    assert_script_run("qvm-service --disable dom0 qubes-update-check");
    assert_script_run("script -a -e -c 'sudo qubes-dist-upgrade --releasever=4.3 --assumeyes --update --max-concurrency=1 --enable-current-testing' release-upgrade.log", timeout => 7200);
    assert_script_run("script -a -e -c 'sudo qubes-dist-upgrade --releasever=4.3 --assumeyes --release-upgrade --enable-current-testing' release-upgrade.log", timeout => 600);
    assert_script_run("script -a -e -c 'sudo qubes-dist-upgrade --releasever=4.3 --assumeyes --dist-upgrade --enable-current-testing' release-upgrade.log", timeout => 7200);
    sleep(1);
    send_key('ctrl-c');

    # reset keyboard layout (but still test if after reboot)
    if (check_var('KEYBOARD_LAYOUT', 'us-colemak')) {
        x11_start_program(us_colemak('setxkbmap us'), valid => 0);
    } elsif (get_var('LOCALE')) {
        x11_start_program('setxkbmap us', valid => 0);
    }
    sleep(1);
    if (check_var("BACKEND", "generalhw")) {
        script_run("systemctl enable sshd");
    } else {
        assert_script_run("systemctl enable serial-getty\@hvc1.service");
    }
}

sub upgrade_whonix_17_to_18 {
    my ($self, $template) = @_;

    assert_script_run ("qvm-run -u root --no-gui -ap $template 'cat /usr/sbin/release-upgrade | grep version='", timeout => 60);
    save_screenshot;
    assert_script_run ("script -a -e -c 'qvm-run -u root --no-gui -ap $template release-upgrade' whonix-upgrade.log", timeout => 1800);
    $self->maybe_unlock_screen;
    assert_script_run ("script -a -e -c 'qvm-run -u root --no-gui -ap $template apt-get update' whonix-upgrade.log", timeout => 600);
    if ($template =~ m/workstation/) {
        assert_script_run ("script -a -e -c 'qvm-run -u root --no-gui -ap $template apt-get -y install qubes-whonix-workstation-gui-lxqt' whonix-upgrade.log", timeout => 1800);
    } else {
        assert_script_run ("script -a -e -c 'qvm-run -u root --no-gui -ap $template apt-get -y install qubes-whonix-gateway-gui-lxqt' whonix-upgrade.log", timeout => 1800);
    }
    $self->maybe_unlock_screen;
    assert_script_run ("script -a -e -c 'qvm-run -u root --no-gui -ap $template apt-get -y autoremove' whonix-upgrade.log", timeout => 1800);
    $self->maybe_unlock_screen;
}

sub upgrade_42_to_43_after_reboot {
    my ($self) = @_;

    assert_script_run("script -a -e -c 'sudo qubes-dist-upgrade --releasever=4.3 --assumeyes --template-standalone-upgrade --enable-current-testing' release-upgrade.log", timeout => 8000);
    $self->maybe_unlock_screen;
    my $templates = script_output('qvm-ls --raw-data --fields name,klass');
    foreach (split /\n/, $templates) {
        next unless /Template/;
        next unless /whonix/;
        s/\|.*//;
        if (/-17/) {
            $self->upgrade_whonix_17_to_18($_);
        }
    }
    $self->maybe_unlock_screen;
    assert_script_run("script -a -e -c 'sudo qubes-dist-upgrade --releasever=4.3 --assumeyes --finalize --enable-current-testing' release-upgrade-post-reboot.log", timeout => 7200);
    $self->maybe_unlock_screen;
}

sub run {
    my ($self) = @_;

    $self->select_gui_console;
    x11_start_program('xterm');
    send_key('alt-f10');
    curl_via_netvm;

    if (check_var('MODIFY_REPO_CONF', '1')) {
        # just any modification, to trigger .rpmnew file
        assert_script_run("echo | sudo tee -a /etc/yum.repos.d/qubes-dom0.repo");
    }

    if (0) {
        my $templates = script_output('qvm-ls --raw-data --fields name,klass');
        foreach (split /\n/, $templates) {
            next unless /Template/;
            s/\|.*//;
            assert_script_run ("qvm-run -u root --no-gui -ap $_ 'dnf config-manager --set-enabled qubes*current-testing; sed -i \"/#deb .*deb.qubes-os.org.*-testing/s/^#//\" /etc/apt/sources.list.d/qubes-r4.list; true'", timeout => 180);
            assert_script_run("qvm-shutdown --wait $_", timeout => 90);
        }
    }

    script_run("pkill xscreensaver");

    #assert_script_run("sudo qubes-dom0-update --enablerepo=qubes-dom0-current-testing -y qubes-dist-upgrade", timeout => 360);
    if (get_var('RELEASE_UPGRADE_REPO')) {
        # like https://raw.githubusercontent.com/marmarek/qubes-dist-upgrade/convert-luks
        my $url = get_var('RELEASE_UPGRADE_REPO');
        my $zip_url = $url;
        $zip_url =~ s#https://github.com/([^/]*/[^/]*)/tree/([^/]*)#https://github.com/$1/archive/$2.zip#;
        assert_script_run("curl -L $zip_url > dist-upgrade.zip");
        assert_script_run("mkdir dist-upgrade && unzip dist-upgrade.zip -d dist-upgrade/");
        assert_script_run("sudo mv -f dist-upgrade/*/qubes-dist-upgrade.sh /usr/sbin/qubes-dist-upgrade");
        assert_script_run("sudo mv -f dist-upgrade/*/scripts/* /usr/lib/qubes/");
        assert_script_run("sudo qubes-dom0-update -y xinput");
    }

    if (check_var("VERSION", "4.0")) {
        upgrade_40_to_41_before_reboot;
        set_var('VERSION', '4.1');
    } elsif (check_var("VERSION", "4.1")) {
        upgrade_41_to_42_before_reboot;
        set_var('VERSION', '4.2');
    } elsif (check_var("VERSION", "4.2")) {
        upgrade_42_to_43_before_reboot;
        set_var('VERSION', '4.3');
    }

    # install qubesteststub module for updated python version
    if (check_var("BACKEND", "qemu")) {
        assert_script_run("sudo sh -c 'cd /root/extra-files; python3 ./setup.py install'");
    }

    if (check_var('UEFI_DIRECT', '1')) {
        # apply changes to grub, since /etc/default/grub wasn't present during
        # initial install_fixups.pm call
        adjust_xen_cmdline;
    }
    set_var('KEEP_SCREENLOCKER', '1');

    script_run("sudo reboot", timeout => 0);
    assert_screen ["bootloader", "luks-prompt", "login-prompt-user-selected"], 300;
    $self->handle_system_startup;

    x11_start_program('xterm');
    send_key('alt-f10');
    curl_via_netvm;

    upload_logs('/home/user/release-upgrade.log', failok => 1);

    if (check_var("VERSION", "4.1")) {
        upgrade_40_to_41_after_reboot;
    } elsif (check_var("VERSION", "4.2")) {
        $self->upgrade_41_to_42_after_reboot;
    } elsif (check_var("VERSION", "4.3")) {
        $self->upgrade_42_to_43_after_reboot;
    }

    upload_logs('/home/user/release-upgrade-post-reboot.log', failok => 1);
    $self->save_and_upload_log('head -20 /etc/qubes/policy.d/*.policy', 'policy-new.txt');
    $self->save_and_upload_log('head -20 /etc/qubes-rpc/policy/*', 'policy-old.txt');

    type_string("exit\n");

    assert_screen("desktop");
}

sub test_flags {
    # without anything - rollback to 'lastgood' snapshot if failed
    # 'fatal' - whole test suite is in danger if this fails
    # 'milestone' - after this test succeeds, update 'lastgood'
    # 'important' - if this fails, set the overall state to 'fail'
    return { fatal => 1, milestone => 1 };
}


sub post_fail_hook {
    my $self = shift;

    script_run "cat /home/user/release-upgrade.log";
    $self->SUPER::post_fail_hook();
    upload_logs('/home/user/release-upgrade.log', failok => 1);
};

1;

# vim: set sw=4 et:
