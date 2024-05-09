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

sub run {
    assert_and_click 'installer-main-hub-target';
    assert_screen 'installer-disk-spoke';
    if (check_var('NUMDISKS', '2')) {
        assert_and_click 'installer-select-disk';
    }
    if (check_var('BACKEND', 'generalhw')) {
        # install on real HW is running with kickstart, which makes anaconda
        # select manual partitioning by default
        assert_and_click 'installer-partitioning-default';
    }
    assert_and_click 'installer-done';
    assert_screen 'installer-disk-luks-passphrase';
    if (match_has_tag('installer-disk-luks-passphrase-inactive')) {
        click_lastmatch;
        wait_still_screen;
    }
    type_string 'lukspass';
    send_key 'tab';
    type_string 'lukspass';
    send_key 'ret';
    if (get_var('INSTALL_OVER_EXISTING')) {
        assert_and_click 'installer-reclaim-space-question';
        assert_and_click 'installer-reclaim-delete-all';
        assert_and_click 'installer-reclaim-confirm';
    }
    assert_screen 'installer-main-hub';
}

1;

# vim: set sw=4 et:
