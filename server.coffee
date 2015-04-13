Db = require 'db'
Plugin = require 'plugin'
Http = require 'http'
Subscription = require 'subscription'

clientId = 2975
clientSecret = '64884f6d595341147a2e976374101524ba3daec0'

exports.onInstall = (config) !->
	if config
		Db.shared.set 'type', config.type

exports.onConfig = (config) !->
	if config && config.type != Db.shared.get('type')
		Db.shared.set 'type', config.type
		Db.shared.remove curPeriod()
		refresh()

exports.onHttp = (request) !->
	userId = +request.path[0]
	code = request.get.code
	request.respond 200, '<html><body><script>close();</script><h1>You can now switch back to the Happening app</h1></body></html>'

	Http.post
		url: 'https://www.strava.com/oauth/token'
		data:
			client_id: clientId
			client_secret: clientSecret
			code: code
		name: 'httpAccess'
		args: [userId]

exports.httpAccess = (userId, data) !->
	data = JSON.parse(data)
	if !data.access_token
		log 'no access token', data
		return

	log 'got data', JSON.stringify(data)

	athlete = data.athlete
	Db.shared.set 'athletes', userId,
		id: athlete.id
		name: athlete.firstname
		avatar: athlete.profile
		weight: athlete.weight

	token = data.access_token
	Db.personal(userId).set 'token', token
	Db.backend.set 'tokens', userId, token

	update userId, token, curPeriod()

exports.hourly = exports.client_refresh = refresh = !->
	for userId, token of Db.backend.get('tokens')
		update userId, token, curPeriod()
		if new Date().getDate() < 2
			update userId, token, prevPeriod()

update = (userId, token, period) !->
	log 'update', userId, period
	after = new Date(period[0..3], period[4..5]-1).getTime()*.001
	before = new Date(period[0..3], period[4..5]).getTime()*.001
	Http.get
		url: 'https://www.strava.com/api/v3/activities'
		data:
			access_token: token
			after: after
			before: before
		name: 'httpActivities'
		args: [userId, period]

exports.httpActivities = (userId, period, data) !->
	data = JSON.parse(data)
	if !data || data.errors
		log 'error', JSON.stringify(data)
		return

	type = Db.shared.get('type') || 'all'

	total = 0
	findRelated = []
	data.forEach (activity) !->
		if activity.athlete_count>1
			# might need to match up with other activity
			groupId = Db.backend.get('related',activity.id)
			if !groupId
				# http request to find out groupId (lowest id of related activities)
				Http.get
					url: 'https://www.strava.com/api/v3/activities/'+activity.id+'/related'
					data: access_token: Db.backend.get('tokens', userId)
					name: 'httpRelated'
					args: [userId, period, activity]
				return
		else
			groupId = activity.id

		log 'type=', type, 'activity type=', activity.type, JSON.stringify(activity)
		if type is 'all' || (activity.type||'').toLowerCase() is type
			log 'adding!'
			writeActivity userId, period, groupId, activity

			total += activity.distance

	Db.shared.set period, 'totals', userId, total

writeActivity = (userId, period, groupId, activity) !->

	Db.shared.set period, 'activities', groupId, activity.id,
		stravaId: activity.id
		distance: activity.distance
		duration: activity.moving_time
		name: activity.name
		time: new Date(activity.start_date).getTime()*.001
		userId: userId

exports.httpRelated = (userId, period, activity, data) !->
	data = JSON.parse(data)
	if !data || data.errors
		log 'error', JSON.stringify(data)
		return

	groupId = activity.id
	data.forEach (relatedActivity) !->
		groupId = Math.min(groupId, relatedActivity.id)

	Db.backend.set 'related', activity.id, groupId # this is a cache
	writeActivity userId, period, groupId, activity
	

exports.client_logout = !->
	userId = Plugin.userId()
	Db.shared.remove curPeriod(), 'totals', userId
	Db.personal(userId).remove 'token'
	Db.backend.remove 'tokens', userId

curPeriod = ->
	d = new Date()
	d.getFullYear() + ('0'+(d.getMonth()+1)).substr(-2)

prevPeriod = ->
	d = new Date()
	if d.getMonth() == 0
		(d.getFullYear()-1) + '12'
	else
		d.getFullYear() + ('0'+(d.getMonth())).substr(-2)

