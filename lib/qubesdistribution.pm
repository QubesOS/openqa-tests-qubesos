# The Qubes OS Project, https://www.qubes-os.org/
#
# Copyright (C) 2014-2017 SUSE LLC
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
# 
package qubesdistribution;
use base 'distribution';
use strict;
use serial_terminal ();

use testapi qw(diag check_var get_var set_var

    record_info
    assert_screen check_screen match_has_tag save_screenshot wait_screen_change wait_still_screen
    type_string type_password wait_serial send_key send_key_until_needlematch
    mouse_hide mouse_set

);

sub init {
    my ($self) = @_;
    $self->SUPER::init();
    $testapi::username = 'user';
    $testapi::password = 'userpass';
    $self->init_consoles();
    # testapi::init override $testapi::serialdev and is called later
    if (!get_var('SERIALDEV')) {
        set_var('SERIALDEV', 'hvc0');
    }
    $self->{script_run_die_on_timeout} = 1;
    $self->set_expected_serial_failures([
        { type => 'soft', message => 'https://github.com/QubesOS/qubes-issues/issues/9803', pattern => qr/irq 23: nobody cared/ },
        { type => 'hard', message => 'dom0 panic', pattern => qr/Hardware Dom0 crashed/ },
    ]);
}


# initialize the consoles needed during our tests
sub init_consoles {
    my ($self) = @_;

    if (check_var('BACKEND', 'qemu')) {
        $self->add_console('root-virtio-terminal', 'virtio-terminal', {});
    } elsif (check_var('BACKEND', 'generalhw')) {
        # do the same as in openqa-serial script
        my $hostid = (get_var('GENERAL_HW_SOL_ARGS') =~ m/--hostid=(\d+)/)[0];
        # don't need password, there is ssh-agent in place
        $self->add_console('root-virtio-terminal', 'ssh-serial',
		{ hostname => "test-$hostid.testnet", password => "", use_ssh_agent => 1 });
        $self->add_console('root-ssh-wifi', 'ssh-serial',
		{ hostname => "192.168.0.100", password => "", use_ssh_agent => 1 });
    }

    $self->add_console('install-shell',  'tty-console', {tty => 2});
    $self->add_console('installation',   'tty-console', {tty => check_var('VIDEOMODE', 'text') ? 1 : 6});
    $self->add_console('root-console',   'tty-console', {tty => 3});
    $self->add_console('user-console',   'tty-console', {tty => 4});
    $self->add_console('log-console',    'tty-console', {tty => 5});

    $self->add_console('x11',            'tty-console', {tty => 1});

    $self->add_console('guivm-vnc',      'vnc-base',    {
                hostname => 'localhost',
                connect_timeout => 3,
                port => 5555,
                description => "sys-gui's VNC",
    });

    return;
}

# Make sure the right user is logged in, e.g. when using remote shells
sub ensure_user {
    my ($user) = @_;
    type_string("su - $user\n") if $user ne 'root';
}

# callback whenever a console is selected for the first time
sub activate_console {
    my ($self, $console) = @_;

    $console =~ m/^(\w+)-(console|virtio-terminal|ssh|shell)/;
    my ($name, $user, $type) = ($1, $1, $2);
    $name = $user //= '';
    $type //= '';
    if ($name eq 'user') {
        $user = $testapi::username;
    }
    elsif ($name eq 'log') {
        $user = 'root';
    }

    testapi::diag "activate_console, console: $console, type: $type";
    if ($type eq 'console') {
        my $nr = 4;
        $nr = 3 if ($name eq 'root');
        $nr = 5 if ($name eq 'log');
        my @tags = ("tty$nr-selected", "text-logged-in-$user", "text-login");
        # we need to wait more than five seconds here to pass the idle timeout in
        # case the system is still booting (https://bugzilla.novell.com/show_bug.cgi?id=895602)
        # or when using remote consoles which can take some seconds, e.g.
        # just after ssh login
        assert_screen \@tags, 60;
        if (match_has_tag("tty$nr-selected") or match_has_tag("text-login")) {
            type_string "$user\n";
            handle_password_prompt();
        }
        elsif (match_has_tag('text-logged-in-root')) {
            ensure_user($user);
        }
        assert_screen "text-logged-in-$user";
        $self->set_standard_prompt($user);
        assert_screen $console;
    }
    elsif ($type eq 'virtio-terminal') {
        serial_terminal::login($user, "$user# ");
    }


    return;
}

sub console_selected {
    my ($self, $console, %args) = @_;
    $args{await_console} //= 1;
    $args{tags}          //= $console;
    $args{ignore}        //= qr{sut|root-virtio-terminal|iucvconn|svirt|root-ssh};
    return unless $args{await_console};
    return if $args{tags} =~ $args{ignore};
    # x11 needs special handling because we can not easily know if screen is
    # locked, display manager is waiting for login, etc.
    #return ensure_unlocked_desktop if $args{tags} =~ /x11/;
    assert_screen($args{tags}, no_wait => 1);
}

sub handle_password_prompt {
    assert_screen "password-prompt";
    type_password();
    send_key('ret');
}

sub script_sudo($$) {
    my ($self, $prog, $wait) = @_;

    my $str = time;
    if ($wait > 0) {
        $prog = "$prog; echo $str-\$?- > /dev/$testapi::serialdev";
    }
    type_string "clear\n";    # poo#13710
    type_string "sudo sh -c \'$prog\'\n";
    handle_password_prompt unless ($testapi::username eq 'root');
    if ($wait > 0) {
        return wait_serial("$str-\\d+-");
    }
    return;
}

# Simplified but still colored prompt for better readability.
sub set_standard_prompt {
    my ($self, $user, $os_type) = @_;
    $user ||= $testapi::username;
    $os_type ||= 'linux';
    my $prompt_sign = $user eq 'root' ? '#' : '$';
    if ($os_type eq 'windows') {
        $prompt_sign = $user eq 'root' ? '# ' : '$$ ';
        type_string "prompt $prompt_sign\n";
    }
    elsif ($os_type eq 'linux') {
        type_string("which tput 2>&1 && PS1=\"\\\[\$(tput bold 2; tput setaf 1)\\\]$prompt_sign\\\[\$(tput sgr0)\\\] \"\n", max_interval => 100);
    }
}

sub become_root {
    my ($self) = @_;

    type_string "sudo -s\n";
    type_string "whoami > /dev/$testapi::serialdev\n";
    wait_serial("root", 10) || die "Root prompt not there";
    type_string "cd /tmp\n";
    $self->set_standard_prompt('root');
    type_string "clear\n";
}

sub init_desktop_runner {
    my ($program, $timeout) = @_;

    send_key 'alt-f2';
    if (!check_screen('desktop-runner', $timeout)) {
        record_info('workaround', 'desktop-runner does not show up on alt-f2, retrying up to three times (see bsc#978027)');
        send_key 'esc';    # To avoid failing needle on missing 'alt' key - poo#20608
        send_key_until_needlematch 'desktop-runner', 'alt-f2', 3, 10;
    }
    sleep(1);
    # krunner may use auto-completion which sometimes gets confused by
    # too fast typing or looses characters because of the load caused (also
    # see below). See https://progress.opensuse.org/issues/18200
    if (check_var('DESKTOP', 'kde')) {
        type_string($program, max_interval => 13);
    }
    else {
        type_string $program;
    }
}

=head2 x11_start_program

  x11_start_program($program [, timeout => $timeout ] [, no_wait => 0|1 ] [, valid => 0|1, [target_match => $target_match, ] [match_timeout => $match_timeout, ] [match_no_wait => 0|1 ]]);

Start the program C<$program> in an X11 session using the I<desktop-runner>
and looking for a target screen to match.

The timeout for C<check_screen> for I<desktop-runner> can be configured with
optional C<$timeout>. Specify C<no_wait> to skip the C<wait_still_screen>
after the typing of C<$program>. Overwrite C<valid> with a false value to exit
after I<desktop-runner> executed without checking for the result. C<valid=1>
is especially useful when the used I<desktop-runner> has an auto-completion
feature which can cause high load while typing potentially causing the
subsequent C<ret> to fail. By default C<x11_start_program> looks for a screen
tagged with the value of C<$program> with C<assert_screen> after executing the
command to launch C<$program>. The tag(s) can be customized with the parameter
C<$target_match>. C<$match_timeout> can be specified to configure the timeout
on that internal C<assert_screen>. Specify C<match_no_wait> to forward the
C<no_wait> option to the internal C<assert_screen>.
If user wants to assert that command was typed correctly in the I<desktop-runner>
she can pass needle tag using C<match_typed> parameter. This will check typed text
and retry once in case of typos or unexpected results (see poo#25972).

The combination of C<no_wait> with C<valid> and C<target_match> is the
preferred solution for the most efficient approach by saving time within
tests.

This method is overwriting the base method in os-autoinst.

=cut

sub x11_start_program {
    my ($self, $program, %args) = @_;
    my $timeout = $args{timeout};
    # enable valid option as default
    $args{valid}         //= 1;
    $args{target_match}  //= $program;
    $args{match_no_wait} //= 0;
    $timeout             //= 15;
    die "no desktop-runner available on minimalx" if check_var('DESKTOP', 'minimalx');
    # Start desktop runner and type command there
    init_desktop_runner($program, $timeout);
    # With match_typed we check typed text and if doesn't match - retrying
    # Is required by firefox test on kde, as typing fails on KDE desktop runnner sometimes
    if ($args{match_typed} && !check_screen($args{match_typed}, $timeout)) {
        send_key 'esc';
        init_desktop_runner($program, $timeout);
    }
    wait_still_screen(1);
    save_screenshot;
    send_key 'ret';
    # Wait on generalhw for runner to disappear, due to HDMI recording delay
    wait_still_screen(3, similarity_level => 70) unless ($args{no_wait} || ($args{valid} && $args{target_match} && !check_var('BACKEND', 'generalhw')));
    return unless $args{valid};
    assert_screen([ref $args{target_match} eq 'ARRAY' ? @{$args{target_match}} : $args{target_match}],
        $args{match_timeout}, no_wait => $args{match_no_wait});
}

=head2 script_run

  script_run($cmd [, timeout => $timeout] [, output => $output] [,quiet => $quiet])

Deprecated mode

  script_run($program, [$timeout])

Run I<$cmd> (by assuming the console prompt and typing the command). After
that, echo hashed command to serial line and wait for it in order to detect
execution is finished. To avoid waiting, use I<$timeout> 0. The C<script_run>
command string must not be terminated with '&' otherwise an exception is
thrown.

Use C<output> to add a description or a comment of the $cmd.

Use C<quiet> to avoid recording serial_results.

<Returns> exit code received from I<$cmd>, or C<undef> in case of C<not> waiting for I<$cmd>
to return.

=cut

sub script_run {
    my ($self, $cmd, @args) = @_;
    my %args = testapi::compat_args(
        {
            timeout => $bmwqemu::default_timeout,
            output => '',
            quiet => undef
        }, ['timeout'], @args);

    if (testapi::is_serial_terminal) {
        testapi::wait_serial($self->{serial_term_prompt}, no_regex => 1, quiet => $args{quiet});
    }
    testapi::type_string("$cmd", max_interval => 150);
    if ($args{timeout} > 0) {
        die "Terminator '&' found in script_run call. script_run can not check script success. Use 'background_script_run' instead."
          if $cmd =~ qr/(?<!\\)&$/;
        my $str = testapi::hashed_string("SR" . $cmd . $args{timeout});
        my $marker = "; echo $str-\$?-" . ($args{output} ? "Comment: $args{output}" : '');
        if (testapi::is_serial_terminal) {
            testapi::type_string($marker, max_interval => 150);
            testapi::wait_serial($cmd . $marker, no_regex => 1, quiet => $args{quiet});
            testapi::type_string("\n");
        }
        else {
            testapi::type_string("$marker > /dev/$testapi::serialdev\n", max_interval => 150);
        }
        my $res = testapi::wait_serial(qr/$str-\d+-/, timeout => $args{timeout}, quiet => $args{quiet});
        return unless $res;
        return ($res =~ /$str-(\d+)-/)[0];
    }
    else {
        testapi::send_key 'ret';
        return;
    }
}


1;
# vim: sw=4 et ts=4:
