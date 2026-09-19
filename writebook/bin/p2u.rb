#!/usr/bin/env ruby
# frozen_string_literal: true

# p2u — command line front end for the P2U/1 presentation compiler.
#
#   bin/p2u validate deck.p2u
#   bin/p2u compile  deck.p2u --render --json
#   bin/p2u export   deck.p2u --to html
#   bin/p2u schema
#   bin/p2u doctor
#
# Normally invoked through the `bin/p2u` wrapper, which finds a modern Ruby.

ENV["RAILS_ENV"] ||= "development"
require_relative "../config/environment"

exit P2u::CLI.start(ARGV)