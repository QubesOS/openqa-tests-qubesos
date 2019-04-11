
# The Qubes OS Project, https://www.qubes-os.org/
#
# Copyright (C) 2019 Marta Marczykowska-Górecka <marmarta@invisiblethingslab.com>
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


sub run {
    # open global-settings
    select_console('x11');
    assert_screen "desktop";

    # open the widget, close it
    assert_and_click('qui-clipboard-open', 'left', 20);
    assert_screen('qui-clipboard-opened', 20);
    send_key('esc');

    # open it again
    assert_and_click('qui-clipboard-open', 'left', 20);

    # click copy from dom0 clipboard
    assert_and_click('qui-clipboard-copy-dom0', 'left', 20);
    assert_screen('qui-clipboard-copied-dom0', 20);

    # exit
    send_key('esc');

}

sub post_fail_hook {
    my ($self) = @_;
    select_console('x11');
    send_key('esc');
    save_screenshot;
    $self->SUPER::post_fail_hook;

};

1;

# vim: set sw=4 et:

