use strict;
use warnings;

package Dancer2::Plugin::Auth::HTTP::Basic::DWIW;
# ABSTRACT: HTTP Basic authentication plugin for Dancer2 that does what I want.

use MIME::Base64;
use Dancer2::Plugin;

our $HANDLERS = {
    check_login       => undef,
    check_login_async => undef,
    no_auth           => undef,
};

register http_basic_auth => sub {
    my ($dsl, $stuff, $sub, @other_stuff) = @_;

    my $realm = plugin_setting->{'realm'} // 'Please login';

    return sub {
        my $handle_error = sub {
            my ($dsl, $status) = @_;

            $dsl->header('WWW-Authenticate' => 'Basic realm="' . $realm . '"');
            $dsl->status($status);

            if(my $handler = $HANDLERS->{no_auth}) {
                if(ref($handler) eq 'CODE') {
                    return $handler->();
                }
            }
        };

        local $@ = undef;
        eval {
            my $header = $dsl->app->request->header('Authorization') || die \401;

            my ($auth_method, $auth_string) = split(' ', $header);

            $auth_method ne 'Basic' || $auth_string || die \400;

            my ($username, $password) = split(':', decode_base64($auth_string), 2);

            $username || $password || die \401;

            if(my $handler = $HANDLERS->{check_login}) {
                if(ref($handler) eq 'CODE') {
                    my $check_result = eval { $handler->($username, $password); };

                    if($@) {
                        die \500;
                    }

                    if(!$check_result) {
                        die \401;
                    }
                }
            }
            elsif($handler = $HANDLERS->{check_login_async}) {
                if(ref($handler) eq 'CODE') {
                    return $dsl->delayed(sub {
                        $handler->(
                            $username, $password,
                            sub {
                                my ($valid) = @_;
                                if($valid) {
                                    $sub->($dsl, @other_stuff);
                                }
                                else {
                                    $handle_error->($dsl, 401);
                                }
                            },
                        );
                    });
                }
            }
        };

        unless ($@) {
            return $sub->($dsl, @other_stuff);
        }
        else {
            my $error_code = ${$@};
            return $handle_error->($dsl, $error_code);
        }
    };
};

register http_basic_auth_login => sub {
    my ($dsl) = @_;
    my $app = $dsl->app;

    my @auth_header = split(' ', $dsl->app->request->header('Authorization'));
    my $auth_string = $auth_header[1];
    my @auth_parts  = split(':', decode_base64($auth_string), 2);

    return @auth_parts;
},
{
    is_global => 0
};

register http_basic_auth_set_check_handler => sub {
    my ($dsl, $handler) = @_;

    warn 'This is deprecated! Please use http_basic_auth_handler check_login => sub {}';
    $dsl->http_basic_auth_handler(check_login => $handler);
};

register http_basic_auth_handler => sub {
    my ($dsl, $name, $handler) = @_;
    $HANDLERS->{$name} = $handler;
};

register_plugin for_versions => [2];
1;
__END__

=pod

=head1 SYNOPSIS

    package test;

    use Dancer2;
    use Dancer2::Plugin::Auth::HTTP::Basic::DWIW;

    http_basic_auth_handler check_login => sub {
        my ( $user, $pass ) = @_;

        # you probably want to check the user in a better way
        return $user eq 'test' && $pass eq 'bla';
    };

    http_basic_auth_handler no_auth => sub {
        template 'auth_error';
    };

    get '/' => http_basic_auth required => sub {
        my ( $user, $pass ) = http_basic_auth_login;

        return $user;
    };
    1;

=head1 DESCRIPTION

This plugin gives you the option to use HTTP Basic authentication with Dancer2.

You can set a handler to check the supplied credentials. If you don't set a handler, every username/password combination will work.

=head1 CAUTION

Don't ever use HTTP Basic authentication over clear-text connections! Always use HTTPS!

The only case were using HTTP is ok is while developing an application. Don't use HTTP because you think it is ok in corporate networks or something alike, you can always have bad bad people in your network..

=head1 CONFIGURATION

=over 4

=item realm

The realm presented by browsers in the login dialog.

Defaults to "Please login".

=back

=head1 OTHER

This is my first perl module published on CPAN. Please don't hurt me when it is bad and feel free to make suggestions or to fork it on GitHub.

=head1 BUGS

Please report any bugs or feature requests to C<littlefox at fsfe.org>, or through
the web interface at L<https://github.com/LittleFox94/Dancer2-Plugin-Auth-HTTP-Basic-DWIW/issues>.  I will be notified, and then you'll
automatically be notified of progress on your bug as I make changes.

=head1 SUPPORT

After installation you can find documentation for this module with the perldoc command:

    perldoc Dancer2::Plugin::Auth::HTTP::Basic::DWIW

=cut
