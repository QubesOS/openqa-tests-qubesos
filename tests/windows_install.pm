# The Qubes OS Project, https://www.qubes-os.org/
#
# Copyright (C) 2022 Marek Marczykowski-Górecki <marmarek@invisiblethingslab.com>
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
    my $windows_version = get_required_var("WINDOWS_VERSION");

    $self->select_gui_console;
    x11_start_program('xterm');
    send_key('alt-f10');
    curl_via_netvm;


    if (get_var('QWT_DOWNLOAD')) {
        my $qwt_url = get_var('QWT_DOWNLOAD');
        if ($qwt_url =~ m/\.rpm$/) {
            assert_script_run("curl -L $qwt_url > qwt.rpm", timeout => 120);
            assert_script_run("sudo rpm -Uhv --replacepkgs ./qwt.rpm");
        } elsif ($qwt_url =~ m/\.iso$/) {
            assert_script_run("curl -L $qwt_url > qwt.iso", timeout => 120);
            assert_script_run("sudo cp --remove-destination qwt.iso /usr/lib/qubes/qubes-windows-tools.iso");
        } else {
            die "$qwt_url not supported";
        }
    }
    assert_script_run("curl -L https://github.com/elliotkillick/qvm-create-windows-qube/raw/master/install.sh > install.sh");
    #assert_script_run("sha256sum -c <<<'a3f8b18da2b0590fb418ccd09c6aabcdfe6da45087077ab961da0fdaa5b43867  install.sh'");

    assert_script_run('chmod +x install.sh');

    assert_script_run("./install.sh", timeout => 1800);

    assert_script_run("sudo sed -i -e 's/qvm-run -q/qvm-run -p/' /usr/bin/qvm-create-windows-qube");

    assert_script_run("qvm-prefs -D windows-mgmt netvm");

    my $windows_iso = "$windows_version.iso";
    if (get_var("ASSET_1")) {
        assert_script_run("qvm-run -p -- windows-mgmt curl -Lo qvm-create-windows-qube/windows/isos/" . get_var("ASSET_1") . " " . data_url("ASSET_1"), timeout => 1800);
        $windows_iso = get_var("ASSET_1");
    } else {
        assert_script_run("qvm-run -p -- windows-mgmt qvm-create-windows-qube/windows/isos/download-windows.sh $windows_version", timeout => 1800);
    }

    assert_script_run("qvm-prefs windows-mgmt netvm ''");

    my $answers_file = "$windows_version.xml";
    $answers_file = 'win10x64-pro.xml' if ($windows_version eq "win10x64");
    $answers_file = 'win11x64-pro.xml' if ($windows_version eq "win11x64");

    my $extra_opts = "";
    $extra_opts .= "--seamless" if ( check_var("QWT_SEAMLESS", "1") );

    # point for interactive pause
    check_screen('NO-MATCH');

    assert_script_run("script -e -c 'bash -x /usr/bin/qvm-create-windows-qube $extra_opts -i $windows_iso -a $answers_file windows-test' qvm-create-windows-qube.log", timeout => 7200);

    sleep(5);

    # enable networking
    assert_script_run("qvm-prefs -D windows-test netvm");

    type_string("exit\n");
};

sub post_fail_hook {
    my $self = shift;

    sleep(5);
    save_screenshot;
    $self->SUPER::post_fail_hook();
    upload_logs('/home/user/qvm-create-windows-qube.log', failok => 1);
};

1;

