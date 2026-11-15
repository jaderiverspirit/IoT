# Executed exclusively INSIDE the local GitLab container via gitlab-rails.
# Using the official documented Rails PAT API, not a guessed web API.
user = User.find_by_username('root')
raise 'GitLab root user does not exist' unless user

name = 'IoT local lab bootstrap'
user.personal_access_tokens.where(name: name).each(&:revoke!)
pat = user.personal_access_tokens.create!(
  name: name,
  scopes: ['api'],
  expires_at: 90.days.from_now
)
pat.set_token(ENV.fetch('IOT_GITLAB_PAT'))
pat.save!
puts 'IoT GitLab bootstrap token created successfully'
