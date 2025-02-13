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
    my $failed = 0;

    $self->select_gui_console;
    x11_start_program('xterm');
    send_key('alt-f10');
    become_root;
    curl_via_netvm;

    die "Set NUMDISKS >= 2" unless get_var('NUMDISKS') >= 2;
    if (get_var('PARTITIONING') eq 'standard') {
        assert_script_run('printf "label: gpt\n,,L" | sfdisk /dev/sdb');
        assert_script_run('mkfs.ext4 -F /dev/sdb1');
        assert_script_run('printf "/dev/sdb1 /var/lib/qubes-pool ext4 defaults 0 0" >> /etc/fstab');
        assert_script_run('mkdir -p /var/lib/qubes-pool');
        assert_script_run('mount /var/lib/qubes-pool');
        assert_script_run('qvm-pool add --option dir_path=/var/lib/qubes-pool pool-test file');
    } elsif (get_var('PARTITIONING') eq 'btrfs') {
        assert_script_run('printf "label: gpt\n,,L" | sfdisk /dev/sdb');
        assert_script_run('mkfs.btrfs /dev/sdb1');
        assert_script_run('printf "/dev/sdb1 /var/lib/qubes-pool btrfs defaults 0 0" >> /etc/fstab');
        assert_script_run('mkdir -p /var/lib/qubes-pool');
        assert_script_run('mount /var/lib/qubes-pool');
        assert_script_run('qvm-pool add --option dir_path=/var/lib/qubes-pool pool-test file-reflink');
    } elsif (get_var('PARTITIONING') eq 'xfs') {
        assert_script_run('rpm -q xfsprogs || qubes-dom0-update -y xfsprogs', timeout => 300);
        assert_script_run('printf "label: gpt\n,,L" | sfdisk /dev/sdb');
        assert_script_run('mkfs.xfs /dev/sdb1');
        assert_script_run('printf "/dev/sdb1 /var/lib/qubes-pool xfs defaults 0 0" >> /etc/fstab');
        assert_script_run('mkdir -p /var/lib/qubes-pool');
        assert_script_run('mount /var/lib/qubes-pool');
        assert_script_run('qvm-pool add --option dir_path=/var/lib/qubes-pool pool-test file-reflink');
    } elsif (get_var('PARTITIONING') eq 'zfs') {
        assert_script_run('qubes-dom0-update -y zfs', timeout => 900);
        assert_script_run('modprobe zfs zfs_arc_max=67108864');

        assert_script_run('printf "label: gpt\n,,L" | sfdisk /dev/sdb');
        assert_script_run('zpool create -f testpool /dev/sdb1');
        assert_script_run('qvm-pool add --option container=testpool pool-test zfs');
    } else {
        die "Invalid PARTITIONING value";
    }

    assert_script_run('qubes-prefs default-pool pool-test');

    my $migrate_templates = <<ENDCODE;
migrate_templates() {
    templates=\$(qvm-ls --raw-data --fields=name,class|grep 'TemplateVM\$'|cut -f 1 -d '|')
    for tpl in \$templates; do
        echo "Migrating \$tpl"
        qvm-clone -P pool-test \$tpl \$tpl-pool || return 1
        for vm in \$(qvm-ls --raw-data --fields=name,template|grep "\$tpl\\\$"|cut -f 1 -d '|'); do
            echo "Switching vm \$vm"
            qvm-prefs \$vm template \$tpl-pool || return 1
        done
    done
    qubes-prefs default-template \$(qubes-prefs default-template)-pool
    for tpl in \$templates; do
        echo "Removing \$tpl"
        qvm-prefs \$tpl installed_by_rpm false
        qvm-remove -f \$tpl || return 1
    done
}
ENDCODE
    chop($migrate_templates);
    assert_script_run($migrate_templates);

    if (get_var("TEST_TEMPLATES")) {
        my $test_templates = get_var("TEST_TEMPLATES");
        $test_templates =~ s/([^ ]+)/\1-pool/g;
        set_var("TEST_TEMPLATES", $test_templates);
    }

    assert_script_run('qvm-shutdown --all --wait');

    assert_script_run('migrate_templates', timeout => 1800);

    assert_script_run('qvm-start sys-firewall sys-usb', timeout => 240);
    assert_script_run('! qvm-check sys-whonix || qvm-start sys-whonix');
    type_string("exit\n");
    type_string("exit\n");
};

1;

