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
    assert_screen("securedrop-launcher-updates-complete", timeout => 1500);
    if (check_screen("securedrop-launcher-updates-complete-reboot")) {
        assert_and_click("securedrop-launcher-updates-complete-reboot");
        $self->handle_system_startup;
        assert_and_click("securedrop-launch-from-desktop-icon", dclick => 1);
    } else {
        assert_and_click("securedrop-launcher-updates-complete-continue");
    }
    if (check_screen(
        'securedrop-client-login-screen',
         30  # necessary due to race condition https://github.com/freedomofpress/securedrop-workstation/issues/1336
        )) {
        send_key('alt-f4');  # exit SecureDrop client
    }

    x11_start_program('xterm');
    send_key('alt-f10');  # maximize xterm to ease troubleshooting

    # Suppress sd-client autostart (already verified as working earlier in script)
    assert_script_run('rm /home/user/.config/autostart/press.freedom.SecureDropUpdater.desktop');

    # Upload packages
    $self->upload_packages_versions(failok=>1);

}

sub post_fail_hook {
    my $self = shift;

    $self->SUPER::post_fail_hook();
    upload_logs('/home/user/.securedrop_updater/logs/updater.log', failok => 1);
    upload_logs('/home/user/.securedrop_updater/logs/updater-detail.log', failok => 1);

    # sdw-admin --apply
    upload_logs('/tmp/sdw-admin-apply.log', failok => 1);

    $self->upload_packages_versions(failok=>1);

};

1;

# vim: set sw=4 et:
