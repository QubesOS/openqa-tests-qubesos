# The Qubes OS Project, https://www.qubes-os.org/
#
# Copyright (C) 2026 Frédéric Pierret (fepitre) <frederic@insiblethingslab.com>
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
use serial_terminal qw(select_root_console);

sub run {
    my ($self) = @_;

    if (check_var('SKIP_INSTALL', '1')) {
        return;
    }

    # otherwise the commands below are typed at the anaconda screen
    select_root_console();

    my $repos_dir = '/tmp/installer.repos.d';
    my $install_repo = check_var('INSTALL_REPO_PATH_SOURCE', '1');

    # QubesOS/qubes-issues#10844: the ISO install source is a
    # RepoPathSourceModule with no .repository attribute, so WriteRepositoriesTask
    # must call generate_repo_configuration() and write the source repos here.
    # this only happens when the source yields a repo, so require it when install_repo is set
    if ($install_repo) {
        assert_script_run("test -d $repos_dir");
        assert_script_run("ls $repos_dir/*.repo");
        script_run("cat $repos_dir/*.repo");
        # the repo is written by configparser, so baseurl has spaces around the =
        assert_script_run("grep -qE '^[[:space:]]*baseurl[[:space:]]*=' $repos_dir/*.repo");

        # the crash signature must not appear in the installer logs
        assert_script_run(q{! cat /tmp/anaconda.log /tmp/packaging.log /tmp/program.log 2>/dev/null | grep -F "has no attribute 'repository'"});

        # in the #10844 repro the baseurl is the dracut mount, proving a RepoPathSourceModule was handled
        assert_script_run("grep -qr /run/install/repo $repos_dir/");
    }

    select_console('installation');
}

1;
# vim: set sw=4 et:
