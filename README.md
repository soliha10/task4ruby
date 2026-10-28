# User Management (Task #4, Ruby)

A Rails 8 + PostgreSQL admin panel for managing users, with an AI assistant
(Google Gemini with function calling) that answers questions about the users and
controls the table.

## Features

- Registration (name, e-mail, any non-empty password), login, logout.
- Every request except login/registration reloads the current user from the
  database; deleted or blocked users are logged out and sent to the login page
  with an explanation (JSON requests get `401` with a redirect URL).
- Users table (Bootstrap 5): selection checkboxes with "select all"
  (indeterminate state), name + job position, e-mail, last login (relative time
  with exact time in a tooltip), status badge. Sorted by last login (newest
  first) by default; column headers sort the table.
- Toolbar: Block (text + icon), Unblock (icon), Delete (icon), filter input.
  Buttons have tooltips and are disabled while nothing is selected. Rows contain
  no buttons. Users can block/unblock/delete anyone, including themselves
  (blocking/deleting yourself logs you out).
- Deleted users are really deleted and can register again with the same e-mail.
- No animations, no browser `alert()`/`confirm()`; status messages are Bootstrap alerts.
- Assistant panel (right of the table on wide screens, below it on mobile).

## E-mail uniqueness

Uniqueness is guaranteed by the database, not by a model validation. The
migration (`db/migrate/20261022000001_create_users.rb`) creates a
case-insensitive unique index:

```ruby
add_index :users, "lower(email)", unique: true, name: "index_users_on_lower_email"
```

`RegistrationsController` rescues `ActiveRecord::RecordNotUnique` and shows
"Email is already registered". E-mails are also normalized (stripped and
downcased) before saving.

Show the index (e.g. for the demo video):

```sql
-- psql ruby_users_app_development
\d users
SELECT indexname, indexdef FROM pg_indexes WHERE tablename = 'users';
```

```
 index_users_on_lower_email | CREATE UNIQUE INDEX index_users_on_lower_email ON public.users USING btree (lower((email)::text))
```

## Local setup

Requirements: Ruby 3.3+ (developed on 4.0, deployed on 3.4), PostgreSQL.

```sh
bundle install
bin/rails db:create db:migrate db:seed
GEMINI_API_KEY=your-key bin/rails server
```

Open http://localhost:3000. Run the tests with `bin/rails test`.

### Seeded users

`db/seeds.rb` loads the 200 users from `db/seeds/users.json` (`last_seen` is
stored as `last_login_at`). The source data has no passwords, so **every seeded
user has the password `password`**. Seeds only run when the users table is
empty; `RESEED=1 bin/rails db:seed` replaces all users.

## Environment variables

| Variable          | Purpose                                              |
|-------------------|------------------------------------------------------|
| `DATABASE_URL`    | PostgreSQL connection (production)                   |
| `SECRET_KEY_BASE` | Rails secret (production; no master key is needed)   |
| `GEMINI_API_KEY`  | Google AI Studio API key for the assistant           |
| `GEMINI_MODEL`    | Gemini model, default `gemini-2.5-flash`             |
| `APP_HOST`        | Optional extra allowed host (custom domain)          |

Without `GEMINI_API_KEY` the app works normally and the chat answers with a
message that the assistant is not configured.

## Deploying to Render

1. Push the repository to GitHub.
2. In Render choose **New > Blueprint**, select the repository. `render.yaml`
   creates a free PostgreSQL database and a Ruby web service.
3. Enter `GEMINI_API_KEY` when asked (it is `sync: false`).
   `SECRET_KEY_BASE` is generated automatically.
4. The build runs `bin/render-build.sh`: `bundle install`, asset precompilation,
   `db:migrate` and `db:seed` (seeds only when the table is empty).

## AI assistant

`POST /assistant` (JSON, requires login) runs `Assistant::Chat`, which sends the
conversation and function declarations to the Gemini `generateContent` REST API,
executes the requested functions server-side and loops (max 6 rounds) until the
model returns text. The model never counts by itself: every number comes from
ActiveRecord queries in `Assistant::Tools`.

Data tools: `get_current_user`, `count_users`, `list_users`, `user_stats`,
`group_count` (by status, email_domain, job_position, last_login_month).
UI tools: `select_users`, `clear_selection`, `filter_table`, `clear_filter`,
`sort_table`, `perform_action` (block / unblock / delete).

All tools share a filter object, implemented in `app/services/user_filter.rb`:

```json
{ "match": "any",
  "conditions": [ { "field": "email", "op": "starts_with", "values": ["s", "p"] } ] }
```

Fields: `name`, `email`, `email_domain`, `job_position`, `status`,
`last_login_at`. Operators: `equals`, `not_equals`, `contains`, `not_contains`,
`starts_with`, `ends_with`, `regex`, `before`, `after`, `between`, `is_null`,
`not_null`; each condition can be negated.

Chat history is kept in the browser's `sessionStorage` and the last 20 turns are
sent with each request.

### Example questions and commands

- How many users are there? How many are blocked?
- How many users have e-mails starting with "s" or "p"?
- Which e-mail domains are the most common?
- How many users logged in during the last 30 days? Who logged in most recently?
- How many users have a title like Dr. or Mr. in their name? List them.
- How many users per month by last login?
- Who am I?
- Select users whose e-mails start with s or p.
- Show only blocked users. / Show all users again.
- Sort the table by name ascending.
- Clear the selection.
- Block all users whose job position contains "Manager".
- Unblock everyone with an e-mail ending in .example.

## Project layout

```
app/controllers/application_controller.rb   current-user check before each request
app/controllers/sessions_controller.rb       login / logout
app/controllers/registrations_controller.rb  registration (rescues RecordNotUnique)
app/controllers/users_controller.rb          table + block / unblock / delete
app/controllers/assistant_controller.rb      POST /assistant
app/services/user_filter.rb                  filter object -> SQL
app/services/assistant/                      Gemini client, chat loop, tools
app/assets/javascripts/users.js              table selection, filter, chat UI
db/seeds.rb, db/seeds/users.json             seed data
render.yaml, bin/render-build.sh             Render deployment
```
