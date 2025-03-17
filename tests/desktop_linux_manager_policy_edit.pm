# The Qubes OS Project, https://www.qubes-os.org/
#
# Copyright (C) 2024 Marta Marczykowska-Górecka <marmarta@invisiblethingslab.com>
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
    # open policy editor in-blanco
    select_console('x11');
    assert_screen "desktop";
    x11_start_program('qubes-policy-editor-gui');

    # open a file
    assert_and_click('policy-editor-open-file-menu', mousehide => -1);
    assert_and_click('policy-editor-select-open-file', mousehide => 1);
    assert_and_click('policy-editor-select-90-default');
    assert_and_click('policy-editor-select-file');

    assert_screen("policy-editor-90-default-open");
    assert_screen("policy-editor-save-inactive");
    assert_and_click('policy-editor-click-on-comment');
    send_key 'a';
    send_key 'b';
    send_key 'c';

    assert_screen("policy-editor-save-active");

    #make an error
    assert_and_click('policy-editor-click-on-deny');
    send_key 'a';
    send_key 'b';
    send_key 'c';

    assert_screen("policy-editor-error-visible");

    # reset
    assert_and_click('policy-editor-open-edit-menu', mousehide => -1);
    assert_and_click('policy-editor-edit-reset', mousehide => 1);

    assert_screen("policy-editor-no-errors-found");

    # make new file
    send_key("ctrl-n");
    type_string('55-user-test');

    assert_and_click("policy-editor-new-file-confirm");
    type_string('qubes.StartApp +firefox work @dispvm allow');
    assert_and_click('policy-editor-save-exit');

    # open the file
    x11_start_program('qubes-policy-editor-gui 55-user-test', target_match => 'qubes-policy-editor-55-user-test');

    assert_screen("policy-editor-firefox-rule");

    assert_and_click('policy-editor-quit');
    mouse_hide();

}

sub post_fail_hook {
    my ($self) = @_;
    select_console('x11');
    if (!check_screen('desktop', 5)) {
        send_key('alt-f4');
    }
    save_screenshot;
    $self->SUPER::post_fail_hook;

};

1;
