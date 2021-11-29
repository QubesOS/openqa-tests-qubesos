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

use base "installedtest";
use strict;
use testapi;
use networking;

sub run {
    my ($self) = @_;

    select_console('x11');
    x11_start_program('xterm');
    send_key('alt-f10');

    my $new_template = get_var("DEFAULT_TEMPLATE");
    my $migrate_templates = <<ENDCODE;
switch_template() {
    default_template=\$(qubes-prefs default-template)
    new_template=\$(qvm-ls --raw-data --fields=name|grep ^$new_template|head -1)
    if [ "\$default_template" = "\$new_template" ]; then
        echo "\$new_template is already default template"
        return
    fi
    not_running=\$(qvm-ls --raw-data --fields=name,template,state|grep "\$default_template|Halted\$"|cut -f 1 -d '|')
    for vm in \$not_running; do
        echo "Switching \$vm"
        qvm-prefs "\$vm" template "\$new_template" || return 1
    done
    running=\$(qvm-ls --raw-data --fields=name,template,state|grep "\$default_template|Running\$"|cut -f 1 -d '|')
    if [ -n "\$running" ]; then
        echo "Shutting down" \$running
        qvm-shutdown --force --wait \$running
        for vm in \$running; do
            echo "Switching \$vm"
            qvm-prefs "\$vm" template "\$new_template" || return 1
        done
        echo "Starting up" \$running
        qvm-start --skip-if-running \$running || return 1
    fi
    qubes-prefs default-template \$new_template
}
ENDCODE
    chop($migrate_templates);
    assert_script_run($migrate_templates);

    assert_script_run('switch_template', timeout => 1800);
    type_string("exit\n");
    type_string("exit\n");
}

1;

# vim: set sw=4 et:
