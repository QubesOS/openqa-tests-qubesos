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

use base 'anacondatest';
use strict;
use testapi;
use bootloader_setup;

sub run {
    # wait for the installer welcome screen to appear
    assert_screen 'installer', 300;

    # wait for resolution change (on generalhw, there is a background process
    # that calls xrandr shortly after Xorg startup)
    sleep 5;
    # Xorg driver needs few moves to detect tool (sub)device
    mouse_set(0, 0);
    sleep 1;
    mouse_set(100, 100);
    sleep 1;
    mouse_click();
    sleep 1;
    mouse_hide;
    save_screenshot;

    if (check_var('LOCALE', 'en_DK.utf8')) {
        assert_and_click 'installer-language-english-denmark';
    }

    send_key 'f12';
    if (check_screen('installer-prerelease', 20)) {
        assert_and_click 'installer-prerelease';
    }
    if (check_screen 'installer-unsupported-hardware', 20) {
        if (check_var("BACKEND", "qemu")) {
            assert_and_click 'installer-unsupported-hardware';
        } else {
            die "Unexpected 'unsupported hardware' message";
        }
    }
    assert_screen 'installer-main-hub';
}

sub test_flags {
    # 'fatal'          - abort whole test suite if this fails (and set overall state 'failed')
    # 'ignore_failure' - if this module fails, it will not affect the overall result at all
    # 'milestone'      - after this test succeeds, update 'lastgood'
    # 'norollback'     - don't roll back to 'lastgood' snapshot if this fails
    return { fatal => 1 };
}

1;

# vim: set sw=4 et:
