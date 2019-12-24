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

sub run {
    my ($self) = @_;
    my $qvmpci_cmd;
    my $mouse_action;

    assert_screen "desktop";

    select_console('root-virtio-terminal');

    if (get_var('VERSION') =~ /^3/) {
        my $qvmpci_wrapper = <<ENDFUNC;
qvm_pci_wrapper() {
    for dev in \$(qvm-pci \$1); do
        dev=\$(echo "\$dev"|tr -d "[],\\"'")
        [ -n "\$dev" ] || continue
        lspci|grep ^\$dev
    done
}
ENDFUNC
        chop($qvmpci_wrapper);
        assert_script_run($qvmpci_wrapper);
        $qvmpci_cmd = 'qvm_pci_wrapper';
        $mouse_action = 'ask';
    } else {
        $qvmpci_cmd = 'qvm-pci ls';
        $mouse_action = 'allow';
    }


    assert_script_run('xl list');
    if (check_var('USBVM', 'none')) {
        assert_script_run('! xl domid sys-usb');
        assert_script_run('! qvm-check sys-usb');
    } elsif (get_var('USBVM', 'sys-usb') eq 'sys-usb') {
        assert_script_run('xl domid sys-usb');
        assert_script_run('qvm-check --running sys-usb');
        # On Xen >= 4.13 PCI passthrough no longer works on OpenQA (IOMMU strictly required even for PV)
        assert_script_run("$qvmpci_cmd sys-usb|grep USB") unless check_var("VERSION", "4.1");
        assert_script_run("grep \"sys-usb.*dom0.*$mouse_action\" /etc/qubes-rpc/policy/qubes.InputMouse");
        assert_script_run('! grep "sys-net.*dom0.*\(allow\|ask\)" /etc/qubes-rpc/policy/qubes.InputMouse');
        assert_script_run('! grep "sys-usb.*dom0.*\(allow\|ask\)" /etc/qubes-rpc/policy/qubes.InputKeyboard');
    } elsif (check_var('USBVM', 'sys-net')) {
        assert_script_run('! xl domid sys-usb');
        assert_script_run('! qvm-check sys-usb');
        assert_script_run('xl domid sys-net');
        assert_script_run('qvm-check --running sys-net');
        # On Xen >= 4.13 PCI passthrough no longer works on OpenQA (IOMMU strictly required even for PV)
        assert_script_run("$qvmpci_cmd sys-net|grep USB") unless check_var("VERSION", "4.1");
        assert_script_run("grep \"sys-net.*dom0.*$mouse_action\" /etc/qubes-rpc/policy/qubes.InputMouse");
        assert_script_run('! grep "sys-usb.*dom0.*\(allow\|ask\)" /etc/qubes-rpc/policy/qubes.InputMouse');
    }
    select_console('x11');
}

1;

# vim: set sw=4 et:
