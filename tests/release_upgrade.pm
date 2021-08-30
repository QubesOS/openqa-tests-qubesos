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

sub run {
    my ($self) = @_;

    select_console('x11');
    x11_start_program('xterm');
    send_key('alt-f10');
    curl_via_netvm;

    if (check_var('MODIFY_REPO_CONF', '1')) {
        # just any modification, to trigger .rpmnew file
        assert_script_run("echo | sudo tee -a /etc/yum.repos.d/qubes-dom0.repo");
    }

    script_run("pkill xscreensaver");

    assert_script_run("sudo qubes-dom0-update --enablerepo=qubes-dom0-current-testing -y qubes-dist-upgrade", timeout => 120);

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

    # install qubesteststub module for updated python version
    assert_script_run("sudo sh -c 'cd /root/extra-files; python3 ./setup.py install'");

    set_var('VERSION', '4.1');
    if (check_var('UEFI_DIRECT', '1')) {
        # apply changes to grub, since /etc/default/grub wasn't present during
        # initial install_fixups.pm call
        my $extra_xen_opts = 'loglvl=all guest_loglvl=all spec-ctrl=no';
        if (!script_run("grep 'GRUB_CMDLINE_XEN_DEFAULT.*console=' /etc/default/grub")) {
            script_run "sudo sed -i -e 's:console=none:console=vga,com1 $extra_xen_opts:' /etc/default/grub";
        } else {
            script_run "sudo sed -i -e 's:GRUB_CMDLINE_XEN_DEFAULT=\":\\0console=vga,com1 $extra_xen_opts :' /etc/default/grub";
        }
        if (!script_run("grep 'multiboot.*console=' /boot/efi/EFI/qubes/grub.cfg")) {
            script_run "sudo sed -i -e 's:console=none:console=vga,com1 $extra_xen_opts:' /boot/efi/EFI/qubes/grub.cfg";
        } else {
            script_run "sudo sed -i -e 's:multiboot.*:\\0 console=vga,com1 $extra_xen_opts:' /boot/efi/EFI/qubes/grub.cfg";
        }
        my $sed_enable_dom0_console_log = 'sed -i -e \'s:quiet:\0 console=hvc0 console=tty0 qubes.enable_insecure_pv_passthrough:g\'';
        script_run "sudo $sed_enable_dom0_console_log /boot/efi/EFI/qubes/grub.cfg";
        script_run "sudo $sed_enable_dom0_console_log /etc/default/grub";
        set_var('UEFI_DIRECT', '');
        # upload_logs doesn't work here, until reboot
        script_run "sudo cat /etc/default/grub";
        save_screenshot;
        script_run "sudo grep -C 5 vmlinuz /boot/efi/EFI/qubes/grub.cfg";
        save_screenshot;
    }
    set_var('KEEP_SCREENLOCKER', '1');

    script_run("sudo reboot", timeout => 0);
    assert_screen ["bootloader", "luks-prompt", "login-prompt-user-selected"], 300;
    $self->handle_system_startup;

    x11_start_program('xterm');
    send_key('alt-f10');
    curl_via_netvm;

    upload_logs('/home/user/release-upgrade.log', failok => 1);

    assert_script_run("script -a -e -c 'sudo qubes-dist-upgrade --assumeyes --resync-appmenus-features' release-upgrade-post-reboot.log", timeout => 3600);
    upload_logs('/home/user/release-upgrade-post-reboot.log', failok => 1);

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
