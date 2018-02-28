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
use networking;

my $configuring = 0;

sub run {
    my ($self) = @_;

    if (!check_var('UEFI', '1')) {
        # wait for bootloader to appear
        assert_screen "bootloader", 90;

        if (match_has_tag("bootloader-installer")) {
            # troubleshooting
            send_key "down";
            send_key "ret";
            # boot from local disk
            send_key "down";
            send_key "down";
            send_key "down";
            send_key "ret";
        }
    }

    assert_screen "luks-prompt";

    type_string "lukspass";

    send_key "ret";

    assert_screen "firstboot-not-ready", 90;

    assert_and_click "firstboot-qubes";

    if (check_var('USBVM', 'none')) {
        # expect checkbox to be enabled by default and disable it
        assert_and_click('firstboot-qubes-usbvm-enabled', 'left', 5);
    } elsif (get_var('USBVM', 'sys-usb') eq 'sys-usb') {
        assert_screen('firstboot-qubes-usbvm-enabled', 5);
    } elsif (check_var('USBVM', 'sys-net')) {
        assert_screen('firstboot-qubes-usbvm-enabled', 5);
        assert_and_click('firstboot-qubes-usbvm-combine', 'left', 5);
    }
    # TODO: check defaults, select various options

    send_key "f12";

    assert_screen "firstboot-configuring-templates", 90;

    $configuring = 1;
	
    my $timeout = 360;
    if (check_var('INSTALL_TEMPLATES', 'all')) {
        $timeout *= 4;
    }
    if (get_var('INSTALL_TEMPLATES', '') =~ /whonix/) {
        $timeout += 2 * 360;
    }
    if (get_var('INSTALL_TEMPLATES', '') =~ /debian/) {
        $timeout += 1 * 360;
    }
    assert_screen "firstboot-configuring-salt", $timeout;
    assert_screen "firstboot-setting-network", 240;
    assert_screen "firstboot-done", 240;
    send_key "f12";

    assert_screen "login-prompt-user-selected", 60;
    type_string "userpass";
    send_key "ret";

    assert_screen "desktop";
}

sub test_flags {
    # without anything - rollback to 'lastgood' snapshot if failed
    # 'fatal' - whole test suite is in danger if this fails
    # 'milestone' - after this test succeeds, update 'lastgood'
    # 'important' - if this fails, set the overall state to 'fail'
    return { important => 1 };
}

sub post_fail_hook {

    if ($configuring) {
        send_key "ret";
        sleep 2;
        send_key "f12";

        check_screen "login-prompt-user-selected", 30;

        select_console('root-virtio-terminal');
        enable_dom0_network_netvm();
        upload_logs('/var/log/libvirt/libxl/libxl-driver.log');
        unless (script_run('journalctl -b >/tmp/journalctl.log')) {
            upload_logs('/tmp/journalctl.log');
        }
        script_run("echo ------ >/dev/$serialdev; ls -1 /var/log/xen/console/*.log; echo ===== >/dev/$serialdev");
        my $logs = wait_serial(qr/------.*=====/);
        foreach (split(/\n/, $logs)) {
            next if m/^---\|^===/;
            upload_logs($_);
        }
        script_run "xl info >/dev/$serialdev";
        script_run "qvm-prefs sys-net >/dev/$serialdev";
        script_run "qvm-prefs sys-firewall >/dev/$serialdev";
        sleep 5;
        save_screenshot;
    }

};

1;

# vim: set sw=4 et:
