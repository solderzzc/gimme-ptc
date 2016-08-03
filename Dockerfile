FROM ruby:2.1-onbuild
CMD ["ruby ./account_creator.rb && cat accounts.txt"]
