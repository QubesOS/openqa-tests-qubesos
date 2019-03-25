
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
    	x11_start_program('qubes-global-settings');
	
	# change minimal qube memory - fix this when qmemman is less horrible
	# assert_screen_and_click('global-settings-minmem', 'left', 5);
	# send_key('ctrl-a')
	# send_text('400')
	#
	assert_and_click('global-settings-dom0up', 'left', 5);

	# exit global settings
	send_key('ret', 5);

	# check if changes were made
	select_console('root-virtio-terminal');
	assert_script_run('qvm-features dom0 check-updates | grep -v 1', 5);
	
}

sub test_flags {
    # 'fatal'          - abort whole test suite if this fails (and set overall state 'failed')
    # 'ignore_failure' - if this module fails, it will not affect the overall result at all
    # 'milestone'      - after this test succeeds, update 'lastgood'
    # 'norollback'     - don't roll back to 'lastgood' snapshot if this fails
    return { milestone => 1 };
}

sub post_fail_hook {

    select_console('x11');
    send_key "esc";
    save_screenshot;

};

1;

# vim: set sw=4 et:

