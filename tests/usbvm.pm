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

use base "installedtest";
use strict;
use testapi;
use serial_terminal;

sub run {
    my ($self) = @_;
    my $qvmpci_cmd;
    my $mouse_action;
    my $keyboard_action;

    assert_screen "desktop";

    select_root_console();

    $qvmpci_cmd = 'qvm-pci ls';
    # FIXME: system upgraded from R4.0 still has 'allow' here
    if (check_var('VERSION', '4.0') or
            (check_var('VERSION', '4.1') and check_var('RELEASE_UPGRADE', '1'))) {
        $mouse_action = 'allow';
    } elsif (check_var("BACKEND", "generalhw")) {
        # tests/firstboot.pm selects automatic mouse allow on generalhw
        $mouse_action = 'allow';
    } else {
        $mouse_action = 'ask';
    }
    if (check_var("BACKEND", "generalhw")) {
        $keyboard_action = 'allow';
    }

    my $policy_mouse = "/etc/qubes/policy.d/50-config-input.policy";
    my $prefix_mouse = "^qubes.InputMouse[[:space:]].*";
    my $policy_keyboard = "/etc/qubes/policy.d/50-config-input.policy";
    my $prefix_keyboard = "^qubes.InputKeyboard[[:space:]].*";

    if (check_var("VERSION", "4.1")) {
        $policy_mouse = "/etc/qubes-rpc/policy/qubes.InputMouse";
        $prefix_mouse = "";
        $policy_keyboard = "/etc/qubes-rpc/policy/qubes.InputKeyboard";
        $prefix_keyboard = "";
    }

    assert_script_run('xl list');
    if (check_var('USBVM', 'none')) {
        assert_script_run('! xl domid sys-usb');
        assert_script_run('! qvm-check sys-usb');
    } elsif (get_var('USBVM', 'sys-usb') eq 'sys-usb') {
        assert_script_run('xl domid sys-usb');
        assert_script_run('qvm-check --running sys-usb');
        assert_script_run("grep \"${prefix_mouse}sys-usb.*\\(dom0\\|\@adminvm\\).*$mouse_action\" $policy_mouse");
        assert_script_run("! grep \"${prefix_mouse}sys-net.*\\(dom0\\|\@adminvm\\).*\\(allow\\|ask\\)\" $policy_mouse");
        if ($keyboard_action) {
            assert_script_run("grep \"${prefix_keyboard}sys-usb.*\\(dom0\\|\@adminvm\\).*$keyboard_action\" $policy_keyboard");
        } else {
            assert_script_run("! grep \"${prefix_keyboard}sys-usb.*\\(dom0\\|\@adminvm\\).*\\(allow\\|ask\\)\" $policy_keyboard");
        }
    } elsif (check_var('USBVM', 'sys-net')) {
        assert_script_run('! xl domid sys-usb');
        assert_script_run('! qvm-check sys-usb');
        assert_script_run('xl domid sys-net');
        assert_script_run('qvm-check --running sys-net');
        # On Xen >= 4.13 PCI passthrough no longer works on OpenQA (IOMMU strictly required even for PV)
        assert_script_run("$qvmpci_cmd sys-net|grep USB") unless check_var("VERSION", "4.1");
        assert_script_run("grep \"${prefix_mouse}sys-net.*\\(dom0\\|\@adminvm\\).*$mouse_action\" $policy_mouse");
        assert_script_run("! grep \"${prefix_mouse}sys-usb.*\\(dom0\\|\@adminvm\\).*\\(allow\\|ask\\)\" $policy_mouse");
    }
    select_console('x11');
}

1;

# vim: set sw=4 et:
