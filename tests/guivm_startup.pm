# The Qubes OS Project, https://www.qubes-os.org/
#
# Copyright (C) 2020 Marek Marczykowski-Górecki <marmarek@invisiblethingslab.com>
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
use serial_terminal;

sub run {
    my ($self) = @_;

    $self->select_gui_console;
    assert_screen "desktop";
    my $vm = 'sys-gui';

    if (get_var('GUIVM_VNC')) {
        $vm = 'sys-gui-vnc';
    }

    # FIXME: change to serial console, don't assume x11 session in dom0
    x11_start_program('xterm');
    assert_script_run("qubes-prefs default_guivm $vm");
    assert_script_run("qvm-shutdown --all --wait && sleep 2 && qvm-start sys-firewall && { ! qvm-check sys-usb || qvm-start sys-usb; }", 180+180+90);
    # reset SSH console if applicable
    if (check_var("BACKEND", "generalhw")) {
        console("root-virtio-terminal")->reset;
    }
    assert_script_run("! qvm-check sys-whonix || time qvm-start sys-whonix", 90);
    assert_script_run("tail -F /var/log/xen/console/guest-$vm.log >> /dev/$testapi::serialdev & true");
    assert_script_run("qvm-start --skip-if-running $vm");

    type_string("exit\n");

    if (get_var('GUIVM_VNC')) {
        # FIXME: make it packaged, rc.local or such
        select_root_console();
        if (check_var("VERSION", "4.1")) {
            assert_script_run("echo -e '$testapi::password\n$testapi::password' | qvm-run --nogui -p -u root $vm 'passwd --stdin user'");
        } else {
            # 'passwd' is not installed by default...
            assert_script_run("echo '$testapi::password' | qvm-run --nogui -p -u root $vm 'hash=\$(openssl passwd -6 -stdin) && sed -i \"s,^user:[^:]*,user:\$hash,\" /etc/shadow'");
        }
        # Force 1024x768 so openQA is happy
        assert_script_run("qvm-run --nogui -pu root sys-gui-vnc env XAUTHORITY=/var/run/lightdm/root/:0 xrandr -s 1024x768");

        select_console('guivm-vnc');
        type_string $testapi::password;
        send_key "ret";

        $self->set_gui_console('guivm-vnc');
        assert_screen("desktop", timeout => 120);
    } else {
        assert_and_click("panel-user-menu");
        assert_and_click("panel-user-menu-logout");
        assert_and_click("panel-user-menu-confirm");

        assert_screen("login-prompt-user-selected");
        assert_and_click("login-prompt-session-type-menu");
        assert_and_click("login-prompt-session-type-gui-domains");
        type_string $testapi::password;
        send_key "ret";

        assert_screen("desktop", timeout => 120);

        # FIXME: make it packaged, rc.local or such
        select_root_console();
        if (check_var("VERSION", "4.1")) {
            assert_script_run("echo -e '$testapi::password\n$testapi::password' | qvm-run --nogui -p -u root $vm 'passwd --stdin user'");
        } else {
            # 'passwd' is not installed by default...
            assert_script_run("echo '$testapi::password' | qvm-run --nogui -p -u root $vm 'hash=\$(openssl passwd -6 -stdin) && sed -i \"s,^user:[^:]*,user:\$hash,\" /etc/shadow'");
        }
        $self->select_gui_console;

        # for some reason, at the very first GUIVM start, the panel fails to load the icons
        if (check_var("VERSION", "4.1")) {
            x11_start_program('xfce4-panel --restart', valid=>0);
        }
        wait_still_screen();
        assert_screen('x11');
    }

}

sub post_fail_hook {
    my ($self) = @_;
    save_screenshot;
    $self->SUPER::post_fail_hook;

};

1;

# vim: set sw=4 et:

