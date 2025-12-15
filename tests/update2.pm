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
use Mojo::File qw(path);

sub uniq { my %seen; grep !$seen{$_}++, @_ };

sub run {
    my ($self) = @_;

    $self->select_gui_console;
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
    if (check_var("BACKEND", "qemu")) {
        type_string "cd /root/extra-files\n";
        type_string "rm -rf /usr/local/lib/python3*/site-packages/qubesteststub*\n";
        type_string "python3 ./setup.py install --prefix=/usr\n";
        type_string "cd -\n";
    }

    if (get_var("UPDATE")) {
        assert_script_run('cp -a /root/extra-files/update /srv/salt/');
        assert_script_run('qubesctl top.enable update');
    }
    my $pillar_dir = "/srv/pillar/base/update";
    assert_script_run("mkdir -p $pillar_dir");
    assert_script_run("printf 'update:\\n  qubes_ver: \"" . get_var('VERSION') . "\"\\n' > $pillar_dir/init.sls");
    my $repo_url = "";
    if (get_var('REPO_1')) {
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
            #assert_script_run("curl -f $key_url > /srv/salt/update/update-key.asc");
            assert_script_run("curl -f $repo_url/key.pub > /srv/salt/update/update-key.asc");
            assert_script_run("printf '  key: update-key\\n' >> $pillar_dir/init.sls");
        }
    }
    # workaround for https://github.com/osresearch/heads/issues/1499
    if (!check_var("HEADS", "1")) {
        assert_script_run("printf '  aem: True\\n' >> $pillar_dir/init.sls");
    }
    assert_script_run("printf \"base:\\n  '*':\\n    - update\\n\" > $pillar_dir/init.top");
    assert_script_run('qubesctl top.enable update pillar=True');
    if (get_var("SALT_SYSTEM_TESTS")) {
        assert_script_run('cp -a /root/extra-files/system-tests /srv/salt/');
        assert_script_run('qubesctl top.enable system-tests');
    }

    assert_script_run('systemctl restart qubesd');
    assert_script_run('(set -o pipefail; qubesctl --show-output state.highstate 2>&1 | tee qubesctl-upgrade.log; ret=$?; qvm-run --nogui -- sys-usb qubes-input-trigger --all; exit $ret)', timeout => 9000);
    if (check_var('KERNEL_VERSION', 'latest')) {
        assert_script_run('qubes-dom0-update -y kernel-latest kernel-latest-qubes-vm', timeout => 600);
        my $latest_kernel = script_output('ls -1v /var/lib/qubes/vm-kernels|grep "^[0-9]" |tail -1');
        assert_script_run("qubes-prefs default-kernel $latest_kernel");
    }
    # disable salt states again
    script_run('rm -f /srv/salt/_tops/base/*');

    # re-do after updating formula package too
    if (get_var("UPDATE_TEMPLATES") =~ /whonix-(gw|gateway)-(\d+)/) {
        my $whonix_vers = $2;
        assert_script_run("qvm-shutdown --wait sys-whonix", timeout => 90);
        assert_script_run("sudo qubesctl top.enable qvm.anon-whonix");
        assert_script_run("(set -o pipefail; sudo qubesctl state.highstate pillar=\"{'qvm':{'whonix':{'version': $whonix_vers}}}\" 2>&1 | tee qubesctl-whonix.log)", timeout => 1800);
        upload_logs("qubesctl-whonix.log");
        assert_script_run("sudo qubesctl top.disable qvm.sys-whonix");
        assert_script_run("qvm-start sys-whonix", timeout => 90);
    }

    # Instead of
    # https://github.com/QubesOS/qubes-core-admin-addon-whonix/pull/24, until
    # Whonix 18 happens
    script_run("qvm-prefs whonix-workstation-17 memory 500");
    script_run("qvm-prefs whonix-workstation-18 memory 500");

    my $targets="--templates";
    if (get_var('TEST_TEMPLATES')) {
        # do a reverse map, new->old
        my %template_map = split /[ :]/, (get_var("DISTUPGRADE_TEMPLATES", "") =~ s/(\S*):(\S*)/\2:\1/gr);
        my @templates_to_update = ();
        foreach (split / /, get_var('TEST_TEMPLATES')) {
            if ($template_map{$_}) {
                push @templates_to_update, $template_map{$_};
            } else {
                push @templates_to_update, $_;
            }
        }
        $targets = '--targets=' . join(",", uniq(@templates_to_update));
    }

    # check if there is anything in the VM repo, otherwise disable it
    # FIXME: don't hardcode bookworm here, maybe simply have some extra job setting
    if (script_run("curl -vf $repo_url/vm/dists/bookworm/Release >/dev/null") != 0) {
        $repo_url = "";
    }
    assert_script_run("sed -i 's%\@REPO_URL\@%$repo_url%' /root/extra-files/update/atestrepo.py");
    assert_script_run("sed -i \"s%\@REPO_KEY\@%\$(cat /srv/salt/update/update-key.asc | sed -z 's:\\n:\\\\n:g')%\" /root/extra-files/update/atestrepo.py");
    assert_script_run("sed -i 's%\@QUBES_VER\@%" . get_var('VERSION') . "%' /root/extra-files/update/atestrepo.py");
    assert_script_run("sed -i 's%\@WHONIX_REPO\@%" . get_var('WHONIX_REPO', 'testers') . "%' /root/extra-files/update/atestrepo.py");
    assert_script_run("cp /root/extra-files/update/atestrepo.py /usr/lib/python3.*/site-packages/vmupdate/agent/source/plugins/");
    if (get_var("SALT_SYSTEM_TESTS")) {
        assert_script_run("cp /root/extra-files/update/systemtests.py /usr/lib/python3.*/site-packages/vmupdate/agent/source/plugins/");
    }

    assert_script_run("script -c 'qubes-vm-update --force-update --log DEBUG --max-concurrency=2 $targets --show-output' -a -e qubesctl-upgrade.log", timeout => 14400);
    upload_logs("qubesctl-upgrade.log");

    # disable all states
    script_run('rm -f /srv/salt/_tops/base/*');
    script_run('rm -f /usr/lib/python3.*/site-packages/vmupdate/agent/source/plugins/atestrepo.py');
    script_run('rm -f /usr/lib/python3.*/site-packages/vmupdate/agent/source/plugins/systemtests.py');

    # minimal net/usb qube
    assert_script_run("qvm-service --enable sys-net minimal-netvm");
    assert_script_run("qvm-service --enable sys-usb minimal-usbvm || :");

    # log package versions
    my $list_tpls_cmd = 'qvm-template list --installed --machine-readable | awk -F\'|\' \'{ print "qubes-template-" $2 "-" gensub("0:", "", 1, $3) }\'';
    $self->save_and_upload_log("(rpm -qa qubes-template-*; $list_tpls_cmd)", 'template-versions.txt');

    # with distupgrade package version will be uploaded later anyway
    if (!get_var("DISTUPGRADE_TEMPLATES")) {
        $self->upload_packages_versions;
    }

    $self->save_and_upload_log('journalctl -b', 'journalctl.log', {timeout => 120});

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
