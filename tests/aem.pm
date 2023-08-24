# The Qubes OS Project, https://www.qubes-os.org/
#
# Copyright (C) 2023 3mdeb Sp. z o.o.
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
use File::Path qw( remove_tree );
use testapi;
use serial_terminal;
use Data::Dumper;
use totp qw(generate_totp);

# The test is affected by a number of variables.
#
# Specific to this test distribution:
#  * TEST_AEM=1          -- enables this test
#  * TEST_AEM_SRK_PASS=1 -- enables use of non-empty SRK password
#  * TEST_AEM_MFA=1      -- enables multi-factor authorization
#
# Defined by os-autoinst:
#  * QEMUTPM_VER=1.2/2.0 -- picks TPM version used by QEMU
#  * BACKEND=qemu        -- has a workaround for TPM1.2 without embedded key

my $totp_secret = undef;

sub run {
    my ($self) = @_;

    handle_poweron();
    handle_luks_pass();
    wait_for_startup();

    setup_tpm();
    install_aem();
    initiate_reboot();

    # first reboot:
    #  - tries to unseal the secret, but fails (this isn't asserted)
    #  - seals the secret successfully
    handle_poweron();
    handle_srk_pass();
    handle_luks_pass();
    assert_screen ["aem-secret.txt-sealed", "aem-secret.otp-sealed"], timeout => 60;
    wait_for_startup();
    initiate_reboot();

    # second reboot:
    #  - unseals the secret successfully
    #  - seals the secret successfully
    handle_poweron();
    handle_srk_pass();
    handle_aem_startup();
    assert_screen ["aem-secret.txt-sealed", "aem-secret.otp-sealed"], timeout => 60;
    wait_for_startup();
}

sub test_flags {
    # without anything - rollback to 'lastgood' snapshot if failed
    # 'fatal' - whole test suite is in danger if this fails
    # 'milestone' - after this test succeeds, update 'lastgood'
    # 'important' - if this fails, set the overall state to 'fail'
    return { important => 1 };
}

sub handle_poweron {
    # wait for bootloader to appear
    assert_screen "bootloader", timeout => 180;
    # skip timeout
    type_string "\n";
}

sub handle_srk_pass {
    if (check_var('TEST_AEM_SRK_PASS', '1')) {
        assert_screen "aem-srk-password-request", timeout => 90;
        type_string "srkpass\n";
    }
}

sub handle_luks_pass {
    assert_screen "luks-prompt", 180;
    type_string "lukspass\n";
}

sub wait_for_startup {
    assert_screen "login-prompt-user-selected", timeout => 90;
    select_root_console();
}

sub initiate_reboot {
    type_string "reboot\n";
    wait_serial qr/reboot/u, 30;
    wait_serial qr/.*#\s*$/u, 30;
    select_console('x11', await_console => 0);
    reset_consoles();
}

sub setup_tpm {
    if (check_var('QEMUTPM_VER', '1.2')) {
        # os-autoinst doesn't do `swtpm_setup --create-platform-cert`, so we
        # have to do this explicitly or nothing will work.
        assert_script_run('systemctl start tcsd');
        assert_script_run('tpm_createek');

        # stopping to make sure that AEM scripts start the service
        assert_script_run('systemctl stop tcsd');
    }

    if (check_var('TEST_AEM_SRK_PASS', '1')) {
        type_string "anti-evil-maid-tpm-setup && echo tpm-setup-done\n";
        wait_serial "Choose SRK password:";
        type_string "srkpass\n";
        wait_serial "Confirm SRK password:";
        type_string "srkpass\n";
        wait_serial "tpm-setup-done";
    } else {
        assert_script_run('anti-evil-maid-tpm-setup -z');
    }
}

sub install_aem {
    # edit configuration to use only PCR[13], which should be non-zero even
    # without DRTM due to being populated by LUKS's header hash
    assert_script_run('sed -i \'s/SEAL=.*/SEAL="--pcr 13"/\' /etc/anti-evil-maid.conf');

    if (check_var('TEST_AEM_MFA', '1')) {
        # make sure time is the same or TOTP won't work out
        assert_script_run("date -s @" . time());

        type_string "anti-evil-maid-install -m /dev/[sv]da1\n";

        # skip warning about installing MFA on internal disk
        wait_serial "Press <ENTER> to continue...";
        send_key "ret";

        wait_serial "Please scan the above QR code";

        # capture and prepare TOTP secret
        my $secret_re = qr/( [A-Z2-7]{4}){8}/;
        my $secret = wait_serial($secret_re);
        $secret =~ s/.*($secret_re).*/$1/s;
        $secret =~ s/ //g;
        $totp_secret = $secret;

        my $totp = generate_totp($secret);
        wait_serial 'Code:';
        type_string "$totp\n";

        my $result = wait_serial qr/TOTP code .+/;
        # up to three attempts, but if two failed something other than time is off
        if ($result =~ 'is invalid') {
            diag "Parsed TOTP secret: $secret";
            $totp = generate_totp($secret);
            wait_serial 'Code:';
            type_string "$totp\n";
            wait_serial 'TOTP code matches';
        }

        wait_serial 'Please enter passphrase:';
        type_string "aemlukspass\n";
        wait_serial 'Please confirm passphrase:';
        type_string "aemlukspass\n";

        wait_serial 'Enter any existing passphrase:';
        type_string "lukspass\n";

        wait_serial 'done';
    } else {
        assert_script_run('anti-evil-maid-install /dev/[sv]da1');
    }

    assert_script_run('echo "really big secret" > /var/lib/anti-evil-maid/aem/secret.txt');
}

sub handle_aem_startup {
    if (check_var('TEST_AEM_MFA', '1')) {
        my $expected_old = generate_totp($totp_secret);
        my $needle = assert_screen "aem-totp-code", timeout => 60;
        my $expected_new = generate_totp($totp_secret);

        # accounting for possible delays by matching one of three areas
        # against up to two codes
        my $code = undef;
        my @ocr = @{$needle->{ocr}};
        for (my $i = 0; $i <= $#ocr; $i++) {
            my $text = $ocr[$i];
            # filtering after capturing more than needed to account for offsets
            # caused by proportional font
            $text =~ s/.*(\d{6}).*/$1/s;
            if ($text eq $expected_old || $text eq $expected_new) {
                $code = $text;
                last;
            }
        }

        if (defined $code) {
            diag "Matched TOTP code: $code";
        } else {
            diag "Didn't match TOTP code: $expected_old, $expected_new";
            diag Dumper @ocr;
            die "TOTP code didn't match, aborting AEM test";
        }

        assert_screen "aem-luks-key-prompt", 180;
        type_string "aemlukspass\n";
    } else {
        assert_screen "aem-good-secret", timeout => 180;
        send_key "ret";
        handle_luks_pass;
    }
}

sub post_run_hook {
    my $self = shift;

    # XXX: this works best on success, not on cancellation and only on some
    #      failures
    if (check_var('BACKEND', 'qemu')) {
        my $tpm_name = get_required_var('QEMUTPM');
        if ($tpm_name eq 'instance') {
            $tpm_name = get_required_var('WORKER_INSTANCE');
        }
        # Start each time with a clean TPM state.
        # Newer os-autoinst cleans the state before starting swtpm.
        remove_tree("/tmp/mytpm$tpm_name");
    }
}

1;

# vim: set sw=4 et:
