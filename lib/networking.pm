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
use File::Basename qw(basename dirname);

use testapi;

our @EXPORT = qw(enable_dom0_network_no_netvm enable_dom0_network_netvm
    curl_via_netvm
);

sub enable_dom0_network_no_netvm {
    return unless script_run('ip r |grep ^default');
    # dhclient not installed by default anymore
    #assert_script_run('dhclient $(ls /sys/class/net|head -1)');
    assert_script_run('dev=$(ls /sys/class/net|head -1)');
    assert_script_run('ip l s $dev up');
    assert_script_run('ip a a 10.0.2.15/24 dev $dev');
    assert_script_run('ip r a default via 10.0.2.2');
    assert_script_run('rm -f /etc/resolv.conf');
    assert_script_run('echo "nameserver 10.0.2.3" > /etc/resolv.conf');
    script_run('ip a; ip r');
}

sub enable_dom0_network_netvm {
    return unless script_run('ip r |grep ^default');

    # if netvm is there, but stuck on boot, kill it
    if (script_run('xl list sys-net |tail -1| grep \' 0.0$\'') == 0) {
        # bypass libvirt intentionally
        script_run('xl destroy sys-net');
    }

    # check if netvm is up
    if (script_run('xl domid sys-net')) {
        # no netvm, bind network device to dom0
        script_run('netdev=$(lspci -n|grep " 0200:"|cut -f 1 -d " ")');
        script_run('xl pci-assignable-remove 0000:$netdev');
        script_run('echo 0000:$netdev > /sys/bus/pci/drivers_probe');
        # dhclient not installed by default anymore
        #assert_script_run('dhclient $(ls /sys/class/net|head -1)');
        assert_script_run('dev=$(ls /sys/class/net|head -1)');
        assert_script_run('ip l s $dev up');
        assert_script_run('ip a a 10.0.2.15/24 dev $dev');
        assert_script_run('ip r a default via 10.0.2.2');
        assert_script_run('echo "nameserver 10.0.2.3" > /etc/resolv.conf');
    } else {
        # there is netvm, connect network through it
        assert_script_run('xl network-attach 0 ip=10.137.99.1 script=/etc/xen/scripts/vif-route-qubes backend=sys-net');
        sleep(2);
        assert_script_run('dev=$(ls /sys/class/net|head -1)');
        assert_script_run('ip a a 10.137.99.1/24 dev $dev');
        assert_script_run('ip l s $dev up');
        assert_script_run('ip r a default dev $dev');
        assert_script_run('rm -f /etc/resolv.conf');
        assert_script_run('echo -e "nameserver 10.139.1.1\nnameserver 10.139.1.2" > /etc/resolv.conf');
        assert_script_run('qubesdb-write -d sys-net /qubes-firewall/10.137.99.1/policy accept');
        # commit
        assert_script_run('qubesdb-write -d sys-net /qubes-firewall/10.137.99.1 ""');
    }
}

=head2

  curl_via_netvm()

Setup curl wrapper that will download/upload a file using sys-net and qvm-run.
It affects only the current shell, and assume the shell is bash (it is a bash
function).

=cut

sub curl_via_netvm {

    my $curl_wrapper = <<ENDFUNC;
curl() {
    local allargs="\$*"
    local inputfile
    if [[ "\$allargs" = *"@"* ]]; then
        inputfile=\${allargs#*@}
        inputfile=\${inputfile%% *}
        allargs=\${allargs/\@\$inputfile/\@-}
    fi

    if [ -n "\$inputfile" ]; then
        qvm-run --no-gui -p sys-net "curl \$allargs" <\$inputfile
    else
        qvm-run --no-gui -p sys-net "curl \$allargs"
    fi
}
ENDFUNC
    save_tmp_file('curl-wrapper.sh', $curl_wrapper);

    assert_script_run("qvm-run --no-gui -p -u root sys-net \"command -v curl || (apt-get update --allow-releaseinfo-change && apt-get -y install curl ) || dnf install -y curl\"", timeout => 120);
    assert_script_run("qvm-run --no-gui -p sys-net \"curl -f " . autoinst_url('/files/curl-wrapper.sh') . "\" > curl-wrapper.sh");
    assert_script_run(". curl-wrapper.sh");
}

1;
# vim: sw=4 et ts=4:
