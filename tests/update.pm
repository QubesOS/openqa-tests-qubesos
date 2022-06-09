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

    select_console('x11');
    assert_screen "desktop";
    x11_start_program('xterm');
    send_key('alt-f10');
    become_root;
    curl_via_netvm;

    # update extra files
    open EXTRA_TARBALL, "tar cz -C " . testapi::get_required_var('CASEDIR') . " extra-files|base64|" or die "failed to create tarball";
    my $tarball = do { local $/; <EXTRA_TARBALL> };
    close(EXTRA_TARBALL);
    save_tmp_file('extra-files.tar.gz.b64', $tarball);

    assert_script_run("curl " . autoinst_url('/files/extra-files.tar.gz.b64') . " | base64 -d | tar xz -C /root");
    type_string "cd /root/extra-files\n";
    type_string "python3 ./setup.py install\n";
    type_string "cd -\n";

    if (get_var("UPDATE")) {
        assert_script_run('cp -a /root/extra-files/update /srv/salt/');
        assert_script_run('qubesctl top.enable update');
    }
    my $pillar_dir = "/srv/pillar/base/update";
    assert_script_run("mkdir -p $pillar_dir");
    assert_script_run("printf 'update:\\n  qubes_ver: \"" . get_var('VERSION') . "\"\\n' > $pillar_dir/init.sls");
    if (get_var('REPO_1')) {
        my $repo_url;
        if (get_var('REPO_1') =~ m/^http/) {
            $repo_url = get_var('REPO_1');
        } else {
            $repo_url = 'https://openqa.qubes-os.org/assets/repo/' .  get_var('REPO_1');
        }
        # Same URL now, since it's availabe directly via Tor too
        assert_script_run("printf '  repo: $repo_url\\n' >> $pillar_dir/init.sls");
        assert_script_run("printf '  repo_onion: $repo_url\\n' >> $pillar_dir/init.sls");
        if (get_var('KEY_1')) {
            my $key_url = get_var('KEY_1');
            assert_script_run("curl -f $key_url > /srv/salt/update/update-key.asc");
            assert_script_run("printf '  key: update-key\\n' >> $pillar_dir/init.sls");
        }
    }
    if (get_var('WHONIX_REPO')) {
       assert_script_run("printf '  whonix_repo: " . get_var('WHONIX_REPO') . "\\n' >> $pillar_dir/init.sls");
    }
    assert_script_run("printf \"base:\\n  '*':\\n    - update\\n\" > $pillar_dir/init.top");
    assert_script_run('qubesctl top.enable update pillar=True');
    if (get_var("SALT_SYSTEM_TESTS")) {
        assert_script_run('cp -a /root/extra-files/system-tests /srv/salt/');
        assert_script_run('qubesctl top.enable system-tests');
    }

    assert_script_run('systemctl restart qubesd');
    assert_script_run('(set -o pipefail; qubesctl --show-output state.highstate 2>&1 | tee qubesctl-upgrade.log)', timeout => 9000);
    if (check_var('KERNEL_VERSION', 'latest')) {
        assert_script_run('qubes-dom0-update -y kernel-latest kernel-latest-qubes-vm', timeout => 600);
        my $latest_kernel = script_output('ls -1v /var/lib/qubes/vm-kernels|grep "^[0-9]" |tail -1');
        assert_script_run("qubes-prefs default-kernel $latest_kernel");
    }
    my $targets="--templates";
    if (get_var('TEST_TEMPLATES')) {
        $targets = '--targets=' . get_var('TEST_TEMPLATES');
        $targets =~ s/ /,/g;
    }
    if (check_var('FLAVOR', 'kernel')) {
        # disable custom repo for VMs - it is empty
        assert_script_run("sed -i -e '/  repo/d' $pillar_dir/init.sls");
    }
    my $ret = script_run("(set -o pipefail; qubesctl --max-concurrency=1 --skip-dom0 $targets --show-output state.highstate 2>&1 | tee -a qubesctl-upgrade.log)", timeout => 14400);
    if ($ret != 0) {
        # make it possible to catch via developer mode
        assert_screen('UPDATE-FAILED');
    }
    upload_logs("qubesctl-upgrade.log");
    assert_script_run('tail -1 qubesctl-upgrade.log|grep -v failed');
    assert_script_run('! grep ERROR qubesctl-upgrade.log');
    assert_script_run('! grep "^  Failed: *[1-9]" qubesctl-upgrade.log');
    assert_script_run('! grep "Failed to return clean data" qubesctl-upgrade.log');

    # disable all states
    script_run('rm -f /srv/salt/_tops/base/*');

    # log package versions
    $self->save_and_upload_log('rpm -qa qubes-template-*', 'template-versions.txt');
    $self->save_and_upload_log('rpm -qa', 'dom0-packages.txt');
    my $templates = script_output('qvm-ls --raw-data --fields name,klass');
    foreach (split /\n/, $templates) {
        next unless /Template/;
        s/\|.*//;
        $self->save_and_upload_log("qvm-run --no-gui -ap $_ 'rpm -qa; dpkg -l; true'",
                "template-$_-packages.txt", {timeout =>90});
        assert_script_run("qvm-shutdown --wait $_", timeout => 90);
    }

    if (check_var('RESTART_AFTER_UPDATE', '1')) {
        type_string("reboot\n");
        assert_screen ["bootloader", "luks-prompt", "login-prompt-user-selected"], 300;
        $self->handle_system_startup;
    } else {
        # only restart key VMs
        # keep sys-net running, to not risk breaking logs upload
        script_run('qvm-shutdown --wait sys-whonix');
        script_run('qvm-shutdown --wait sys-firewall');
        script_run('qvm-kill sys-whonix');
        script_run('qvm-kill sys-firewall');
        assert_script_run('qvm-start sys-firewall', timeout => 90);
        assert_script_run('if qvm-check sys-whonix; then qvm-start sys-whonix; fi', timeout => 90);
        type_string("exit\n");
        type_string("exit\n");
    }
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
    upload_logs('/tmp/qubesctl-upgrade.log', failok => 1);
    script_run('pidof -x qvm-start-gui || echo qvm-start-gui crashed');
};

1;

# vim: set sw=4 et:
