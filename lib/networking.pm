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

package networking;

use base 'Exporter';
use Exporter;

use testapi;

our @EXPORT = qw(enable_dom0_network_no_netvm enable_dom0_network_netvm);

sub enable_dom0_network_no_netvm {
    return unless script_run('ip r |grep ^default');
    assert_script_run('dhclient $(ls /sys/class/net|head -1)');
}

sub enable_dom0_network_netvm {
    return unless script_run('ip r |grep ^default');
    
    # check if netvm is up
    if (script_run('xl domid sys-net')) {
        # no netvm, bind network device to dom0
        script_run('netdev=$(lspci -n|grep " 0200:"|cut -f 1 -d " ")');
        script_run('echo 0000:$netdev > /sys/bus/pci/devices/0000:$netdev/driver/unbind');
        script_run('echo 0000:$netdev > /sys/bus/pci/drivers/pciback/remove_slot');
        script_run('echo 0000:$netdev > /sys/bus/pci/drivers_probe');
        assert_script_run('dhclient $(ls /sys/class/net|head -1)');
    } else {
        # there is netvm, connect network through it
        assert_script_run('xl network-attach 0 ip=10.137.99.1 script=/etc/xen/scripts/vif-route-qubes backend=sys-net');
        assert_script_run('ip a a 10.137.99.1/24 dev eth0');
        assert_script_run('ip l s eth0 up');
        assert_script_run('ip r a default dev eth0');
        assert_script_run('echo -e "nameserver 10.139.1.1\nnameserver 10.139.1.2" > /etc/resolv.conf');
        assert_script_run('qubesdb-write -d sys-net /qubes-firewall/10.137.99.1/policy accept');
        # commit
        assert_script_run('qubesdb-write -d sys-net /qubes-firewall/10.137.99.1 ""');
    }
}

1;
# vim: sw=4 et ts=4:
