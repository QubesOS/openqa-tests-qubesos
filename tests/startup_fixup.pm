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
use networking;

sub run {
    my ($self) = @_;

    select_console('root-virtio-terminal');
    # WTF part
    if (script_run('qvm-check --running sys-net') != 0) {
        assert_script_run('qvm-pci dt sys-net dom0:00_04.0');
        assert_script_run('qvm-pci at sys-net dom0:00_04.0 -p -o no-strict-reset=True');
        assert_script_run('qvm-start sys-net');
        # don't fail if whonix is not installed
        script_run('qvm-start sys-whonix', timeout => 90);
    }
    assert_script_run('echo sys-usb dom0 allow > /etc/qubes-rpc/policy/qubes.InputTablet');
    assert_script_run('qvm-run -u root sys-usb \'systemctl start qubes-input-sender-tablet@$(basename $(readlink /dev/input/by-id/usb-QEMU_QEMU_USB_Tablet_42-event-mouse))\'');
    # force "connection established" notification to show again, if it expired already
    script_run('qvm-run sys-net "killall nm-applet; sleep 1; nm-applet >/dev/null 2>&1 </dev/null & true"', 120);
    select_console('x11');
    assert_screen("nm-connection-established", 60);
    assert_screen("no-notifications");
}

1;

# vim: set sw=4 et:
