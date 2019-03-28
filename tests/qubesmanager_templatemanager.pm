
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
    	x11_start_program('qubes-template-manager');

        # sort by name
        assert_and_click('template-sort', 'left', 15);

        # press reset
        assert_and_click('template-reset', 'left', 20);

        # select two vms
        assert_and_click('template-selectvm1', 'left', 10);
        assert_and_click('template-selectvm2', 'left', 10);

        # change their template to debian
        assert_and_click('template-select-template', 'left', 20);
        assert_and_click('template-select-debian', 'left', 20);

        # clear selection
        assert_and_click('template-clear-selection', 'left', 20);
        
        # change template on another vm
        assert_and_click('template-select-vm-template', 'left', 20);
        assert_and_click('template-change-vm-template', 'left', 20);

        # press ok
        assert_and_click('template-ok', 'left', 20);
        assert_screen('desktop');

        # turn on again
    	x11_start_program('qubes-template-manager');
        
        # press cancel    
        assert_and_click('template-cancel', 'left', 20);

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

