use v5.10;
use strict;
use warnings;

package MooseX::Role::MongoDB;
# ABSTRACT: Provide MongoDB connections, databases and collections
# VERSION

use Moose::Role 2;
use MooseX::AttributeShortcuts;

use MongoDB::MongoClient 0.702;
use Type::Params qw/compile/;
use Types::Standard qw/:types/;
use namespace::autoclean;

#--------------------------------------------------------------------------#
# Public attributes and builders
#--------------------------------------------------------------------------#

=attr client_options

A hash reference of L<MongoDB::MongoClient> options that will be passed to its
C<connect> method.

=cut

has client_options => (
    is  => 'lazy',
    isa => HashRef, # hashlike?
);

sub _build_client_options { return {} }

=attr default_database

The name of a MongoDB database to use as a default collection source if not
specifically requested.  Defaults to 'test'.

=cut

has default_database => (
    is  => 'lazy',
    isa => Str,
);

sub _build_default_database { return 'test' }

#--------------------------------------------------------------------------#
# Private attributes and builders
#--------------------------------------------------------------------------#

has _pid => (
    is      => 'rwp',     # private setter so we can update on fork
    isa     => 'Num',
    default => sub { $$ },
);

has _collection_cache => (
    is      => 'lazy',
    isa     => HashRef,
    clearer => 1,
);

sub _build__collection_cache { return {} }

has _database_cache => (
    is      => 'lazy',
    isa     => HashRef,
    clearer => 1,
);

sub _build__database_cache { return {} }

has _mongo_client => (
    is      => 'lazy',
    isa     => InstanceOf ['MongoDB::MongoClient'],
    clearer => 1,
);

sub _build__mongo_client {
    my ($self) = @_;
    return MongoDB::MongoClient->new( $self->client_options );
}

#--------------------------------------------------------------------------#
# Public methods
#--------------------------------------------------------------------------#

=method mongo_database

    $obj->mongo_database( $database_name );

Returns a L<MongoDB::Database>.  The argument is the database name.

=cut

sub mongo_database {
    state $check = compile( Object, Optional [Str] );
    my ( $self, $database ) = $check->(@_);
    $database //= $self->default_database;
    $self->_check_pid;
    return $self->_database_cache->{$database} //=
      $self->_mongo_client->get_database($database);
}

=method mongo_collection

    $obj->mongo_collection( $database_name, $collection_name );
    $obj->mongo_collection( $collection_name );

Returns a L<MongoDB::Collection>.  With two arguments, the first argument is
the database name and the second is the collection name.  With a single
argument, the argument is the collection name from the default database name.

=cut

sub mongo_collection {
    state $check = compile( Object, Str, Optional [Str] );
    my ( $self, @args ) = $check->(@_);
    my ( $database, $collection ) =
      @args > 1 ? @args : ( $self->default_database, $args[0] );
    $self->_check_pid;
    return $self->_collection_cache->{$database}{$collection} //=
      $self->mongo_database($database)->get_collection($collection);
}

#--------------------------------------------------------------------------#
# Builder documentation
#--------------------------------------------------------------------------#

=method _build_client_options

Returns an empty hash reference.  Override this to provide your own defaults.

=cut

=method _build_default_database

Returns the string 'test'.  Override this to provide your own default.

=cut

#--------------------------------------------------------------------------#
# Private methods
#--------------------------------------------------------------------------#

# check if we've forked and need to reconnect
sub _check_pid {
    my ($self) = @_;
    if ( $$ != $self->_pid ) {
        $self->_set__pid($$);
        $self->_clear_collection_cache;
        $self->_clear_database_cache;
        $self->_clear_mongo_client;
    }
    return;
}

1;

=for Pod::Coverage BUILD

=head1 SYNOPSIS

In your module:

    package MyClass;
    use Moose;
    with 'MooseX::Role::MongoDB';

In your code:

    my $obj = MyClass->new(
        default_database => 'MyDB',
        client_options  => {
            host => "mongodb://example.net:27017",
            username => "willywonka",
            password => "ilovechocolate",
        },
    );

    $obj_>mongo_database("test");                 # test database
    $obj->mongo_collection("books");              # in default database
    $obj->mongo_collection("otherdb" => "books"); # in other database

=head1 DESCRIPTION

This role helps create and manage MongoDB connections and objects.  MongoDB
objects are generated lazily on demand and cached.

The role also compensates for forks.  If a fork is detected, the caches are
cleared and new connections and objects will be generated in the new process.

When using this role, you should not hold onto MongoDB objects for long if
there is a chance of your code forking.  Instead, request them again
each time you need them.

=head1 SEE ALSO

=for :list
* L<MongoDB>

=cut

# vim: ts=4 sts=4 sw=4 et:
