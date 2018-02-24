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

use testapi;

sub enable_dom0_network_no_netvm {
    my $ret = script_run('ip r |grep ^default');
    return if ($ret == 0);
    assert_script_run('dhclient $(ls /sys/class/net|head -1)');
}

sub enable_dom0_network_netvm {
    
}

1;
# vim: sw=4 et ts=4:
