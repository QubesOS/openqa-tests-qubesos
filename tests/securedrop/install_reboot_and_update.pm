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

sub upload_package_lists {
    # Upload inventory of package versions (useful for troubleshooting bad versions)
    # Borrowed from https://github.com/QubesOS/openqa-tests-qubesos/blob/7242736/tests/update2.pm#L121-L138

    my ($self) = @_;

    x11_start_program('xterm');
    send_key('alt-f10');  # maximize xterm to ease troubleshooting

    curl_via_netvm;

    my $fname = $self->save_and_upload_log('rpm -qa', 'dom0-packages.txt');
    my $packages = path('ulogs', $fname)->slurp;
    $packages = join("\n", sort split(/\n/, $packages));
    my $all_packages = "Dom0:\n" . $packages;
    my $templates = script_output('qvm-ls --raw-data --fields name,klass');
    foreach (sort split /\n/, $templates) {
        next unless /Template/;
        s/\|.*//;
        $fname = $self->save_and_upload_log("qvm-run --no-gui -ap $_ 'rpm -qa; dpkg -l; pacman -Q; true'",
                "template-$_-packages.txt");
        $packages = path('ulogs', $fname)->slurp;
        $packages = join("\n", sort split(/\n/, $packages));
        $all_packages .= "\n" . $_ . ":\n" . $packages;
        #assert_script_run("qvm-run --service -p $_ qubes.PostInstall", timeout => 90);
        script_output("qvm-features $_", timeout => 90);
        assert_script_run("qvm-shutdown --wait $_", timeout => 90);
    }
    path("sut_packages.txt")->spew($all_packages);
}

sub run {
    my ($self) = @_;
    $self->select_gui_console;

    x11_start_program('xterm');
    send_key('alt-f10');  # maximize xterm to ease troubleshooting

    # Reboot system
    script_run('sudo reboot', timeout => 0);
    $self->handle_system_startup;

    # HACK Whonix systemcheck still shows up for sys-whonix
    # due to unnapplied updates
    if (check_screen('whonix-systemcheck-derived-repo', timeout => 300)) {
        assert_and_click('whonix-systemcheck-derived-repo-accept');
    }

    # Go through launcher
    assert_and_click("securedrop-launcher");
    assert_screen("securedrop-launcher-updates-in-progress", timeout => 10);
    assert_screen("securedrop-launcher-updates-complete", timeout => 1200);
    if (check_screen("securedrop-launcher-updates-complete-reboot")) {
        assert_and_click("securedrop-launcher-updates-complete-reboot");
        $self->handle_system_startup;
        assert_and_click("securedrop-launch-from-desktop-icon", dclick => 1);
    } else {
        assert_and_click("securedrop-launcher-updates-complete-continue");
    }
    if (check_screen('securedrop-client-login-screen', 5)) {
        send_key('alt-f4');  # exit SecureDrop client
    }

    $self->upload_package_lists;
}

sub post_fail_hook {
    my $self = shift;

    $self->SUPER::post_fail_hook();
    upload_logs('/home/user/.securedrop_updater/logs/updater.log', failok => 1);
    upload_logs('/home/user/.securedrop_updater/logs/updater-detail.log', failok => 1);

    # WIP troubleshooting
    upload_logs('/var/log/xen/console/guest-sd-base-bookworm-template.log', failok => 1);
    upload_logs('/var/log/xen/console/guest-sd-small-bookworm-template.log', failok => 1);
    upload_logs('/var/log/xen/console/guest-sd-large-bookworm-template.log', failok => 1);

    upload_logs('/tmp/sdw-admin-apply.log', failok => 1);
};

1;

# vim: set sw=4 et:
