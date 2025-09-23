# The Qubes OS Project, https://www.qubes-os.org/
#
# Copyright (C) 2025 Marek Marczykowski-Górecki <marmarek@invisiblethingslab.com>
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

    $self->select_gui_console;
    assert_screen "desktop";
    x11_start_program('xterm');
    send_key('alt-f10');
    curl_via_netvm;

    my $gpu_devs = get_required_var("GPU_DEVS");

    assert_script_run('sudo qubes-dom0-update -y qubes-ansible-dom0');
    assert_script_run('mgmt_tpl=$(qvm-prefs $(qubes-prefs management_dispvm) template)');
    assert_script_run('qvm-run -pu root $mgmt_tpl "dnf install -y qubes-ansible-vm || apt-get install -y qubes-ansible-vm"');
    assert_script_run('qvm-shutdown --wait $mgmt_tpl');

    assert_script_run("qvm-template install debian-12-xfce", timeout => 900);

    # update extra files
    open EXTRA_TARBALL, "tar cz -C " . testapi::get_required_var('CASEDIR') . " extra-files/ansible|base64|" or die "failed to create tarball";
    my $tarball = do { local $/; <EXTRA_TARBALL> };
    close(EXTRA_TARBALL);
    save_tmp_file('extra-files.tar.gz.b64', $tarball);

    assert_script_run("curl " . autoinst_url('/files/extra-files.tar.gz.b64') . " | base64 -d | tar xvz");

    assert_script_run("cd extra-files/ansible");
    assert_script_run("set -o pipefail");
    assert_script_run("ansible-playbook -i inventory -e pci_devices=$gpu_devs setup-video.yml |& tee ansible.log", timeout => 600);
    upload_logs("ansible.log");

    assert_script_run("qvm-run -p testvideolin env VGL_DISPLAY=egl vglrun /usr/local/bin/webgl.py", timeout => 60);

}

sub post_fail_hook {
    my ($self) = @_;

    save_screenshot;
    upload_logs("/home/user/extra-files/ansible.log", failok => 1);
    $self->SUPER::post_fail_hook;

};

1;

# vim: set sw=4 et:

