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

# update just enough to update xen in dom0, then reboot

use base "installedtest";
use strict;
use testapi;
use networking;
use Mojo::File qw(path);

sub run {
    my ($self) = @_;

    $self->select_gui_console;
    assert_screen "desktop";
    x11_start_program('xterm');
    send_key('alt-f10');
    become_root;
    curl_via_netvm;

    my $repo_url;
    if (get_var('REPO_1')) {
        if (get_var('REPO_1') =~ m/^http/) {
            $repo_url = get_var('REPO_1');
        } else {
            $repo_url = 'https://openqa.qubes-os.org/assets/repo/' .  get_var('REPO_1');
        }
        if (get_var('KEY_1')) {
            my $key_url = get_var('KEY_1');
            assert_script_run("curl -f $repo_url/key.pub > /etc/pki/rpm-gpg/update-key");
            assert_script_run("rpm --import /etc/pki/rpm-gpg/update-key");
        }
        assert_script_run("echo '[update-test]
name = update test
baseurl = $repo_url/host
gpgkey = file:///etc/pki/rpm-gpg/update-test
gpgcheck = 1
skip_if_unavailable=True
' > /etc/yum.repos.d/update-test.repo");
    }

    my $qubes_ver = get_var('VERSION');
    assert_script_run("echo '[qubes-testing]
name = Qubes updates testing
baseurl = http://yum.qubes-os.org/r$qubes_ver/current-testing/host/fc37
gpgkey = file:///etc/pki/rpm-gpg/RPM-GPG-KEY-qubes-$qubes_ver-primary
gpgcheck = 1
' > /etc/yum.repos.d/qubes-dom0-testing.repo");

    assert_script_run("(set -o pipefail; echo n | qubes-dom0-update --refresh -y --force-xen-upgrade 2>&1 | tee /tmp/dom0-upgrade.log)", timeout => 3600);

    # reboot after update    
    type_string("reboot\n");
    $self->handle_system_startup;

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

    $self->SUPER::post_fail_hook();
    upload_logs('/tmp/dom0-upgrade.log', failok => 1);
};

1;

# vim: set sw=4 et:
