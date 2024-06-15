# The Qubes OS Project, https://www.qubes-os.org/
#
# Copyright (C) 2023 Marek Marczykowski-Górecki <marmarek@invisiblethingslab.com>
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

sub setup_virtual_fido {
    my ($self) = @_;

    $self->select_gui_console;
    assert_screen "desktop";
    x11_start_program('xterm');

    # just install it in sys-usb, to match real case of physical USB token
    assert_script_run("qvm-prefs sys-usb netvm sys-net");
    # move to salt
    assert_script_run("qvm-run -p -u root sys-usb 'dnf install -y usbip golang qubes-u2f || apt-get install -y usbip golang qubes-u2f'", timeout => 240);
    assert_script_run("qvm-run -p -u root fedora-38 'dnf install -y qubes-u2f || apt-get install -y qubes-u2f'", timeout => 240);
    assert_script_run("qvm-shutdown fedora-38");
    assert_script_run("qvm-run -p sys-usb git clone https://github.com/bulwarkid/virtual-fido");
    assert_script_run("qvm-run -p sys-usb 'cd virtual-fido; go build ./cmd/demo'", timeout => 120);
    assert_script_run("qvm-run -p -u root sys-usb modprobe vhci-hcd");
    # autoaccept
    type_string("yes | qvm-run -p -u root sys-usb /home/user/virtual-fido/demo start > $serialdev\n");

    assert_and_click("menu");
    assert_and_click("menu-qubes-tools");
    if (match_has_tag("new-menu")) {
        assert_and_click("menu-qubes-tools-submenu");
    }
    assert_and_click("menu-qubes-global-config");

    assert_screen("qubes-global-config", timeout => 90);
    assert_and_click("global-config-usb-devices");
    # click somewhere on the page, so PgDown will scroll the right side
    assert_and_click("global-config-usb-input-devices");
    sleep(2);
    assert_and_click("global-config-scroll-down");
    assert_and_click("global-config-enable-u2f-proxy");
    sleep(5);
    assert_and_click("global-config-scroll-down");
    # allow 'personal' qube
    assert_and_click("global-config-add");
    assert_and_click("global-config-add-edit");
    send_key("ctrl-a");
    type_string("personal");
    assert_and_click("global-config-add-confirm");
    assert_and_click("global-config-u2f-allow-registering");
    assert_and_click("global-config-okay");
}

sub test_webauthn {
    my ($self) = @_;

    assert_and_click("yubico-test-webauthn");
    # Part 1/2: Registration
    assert_and_click("yubico-next");
    assert_and_click("firefox-security-key-allow");
    assert_screen("yubico-registration-completed");
    assert_and_click("yubico-authenticate");
    # Part 2/2: Authentication
    assert_and_click("yubico-next");
    assert_screen("yubico-authentication-successful");
}

sub run {
    my ($self) = @_;

    $self->setup_virtual_fido;

    # try to start "Firefox" in personal
    assert_and_click("menu");
    assert_and_click("menu-vm-personal");
    wait_still_screen();
    assert_and_click("menu-vm-firefox");
    assert_screen("personal-firefox", timeout => 120);

    # wait for full startup
    sleep(2);

    send_key("ctrl-l");
    type_string("https://demo.yubico.com");
    send_key("ret");

    $self->test_webauthn;

    # TODO: FIDO2 (via playground + enable passwordless), requires
    # chrome/chromium, and it insist on ClientPIN which seems to be broken(?)
    # in virtual-fido
}

1;

# vim: set sw=4 et:
