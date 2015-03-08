Db = require 'db'
Dom = require 'dom'
Modal = require 'modal'
Obs = require 'obs'
Plugin = require 'plugin'
Page = require 'page'
Server = require 'server'
Social = require 'social'
Time = require 'time'
Ui = require 'ui'
{tr} = require 'i18n'

clientId = 2975

exports.render = ->
	if !Db.personal.get('token')
		Dom.div !->
			Dom.style
				height: '100%'
				backgroundImage: "url(#{Plugin.resourceUri('bg0.jpg')})"
				backgroundSize: 'cover'
				backgroundPosition: '50% 50%'
				Box: 'center middle'
				margin: '-8px'
			Dom.div !->
				Dom.style
					padding: '25px'
					maxWidth: '300px'
					textAlign: 'center'

				Dom.div !->
					Dom.style
						color: '#fff'
						textShadow: '0 0 5px #000'
					Dom.richText tr("Track Strava activity in **%1**.", Plugin.groupName())
					Dom.br()
					Dom.text tr("Connect your account to get started.")

				Ui.bigButton !->
					Dom.text tr("Connect with Strava")
				, !->
					# future: we should get url from backend and sign it to prevent tampering (changing userId)
					redirect = encodeURIComponent(Plugin.inboundUrl() + '/' + Plugin.userId())
					Plugin.openUrl "https://www.strava.com/oauth/authorize?client_id=#{clientId}&redirect_uri=#{redirect}&response_type=code&scope=view_private"
		return

	if !Page.state.peek(0)
		Page.state.set 0, curPeriod()

	Obs.observe !->
		period = Page.state.get(0)
		if groupId = +Page.state.get(1)
			renderGroup period, groupId
		else
			renderPeriod period

renderPeriod = (period) !->

	dataO = Db.shared.ref(period)

	Dom.h2 tr("Leaderboard %1 %2", months[+period[4..5]-1], period[0..3])
	Ui.list !->
		dataO.iterate 'totals', (total) !->
			Ui.item !->
				Ui.avatar Plugin.userAvatar(total.key())
				Dom.div !->
					Dom.style Flex: 1
					Dom.text Plugin.userName(total.key())
				Dom.div !->
					Dom.style fontWeight: 'bold'
					Dom.text tr("%1 km", round(total.get()*.001))
		, (total) -> -total.get()

	Social.renderComments path: [period]

	Dom.h2 tr("Activities")
	Ui.list !->
		dataO.iterate 'activities', (groupO) !->
			first = obsFirst(groupO)

			Ui.item !->
				groupO.iterate (activity) !->
					Ui.avatar Plugin.userAvatar(activity.get('userId'))
				Dom.div !->
					Dom.style Flex: 1
					speed = first.get('distance')*3.6/first.get('duration')
					Dom.text tr("%1 at %2 km/h", first.get('name'), round(speed,2))
					Dom.div !->
						Dom.style color: '#aaa', fontSize: '75%'
						Time.deltaText first.get('time')

				Dom.div !->
					Dom.text tr("%1 km", Math.round(first.get('distance')*.001))

				Dom.onTap !->
					Page.nav [period, groupO.key()]

	if Plugin.userIsAdmin()
		Ui.bigButton tr("Logout"), !->
			Server.call 'logout'


renderGroup = (period, id) !->
	group = Db.shared.ref(period, 'activities', id)
	first = obsFirst(group)
	if !Page.state.peek(2)
		Page.state.set 2, first.key()
	Dom.div !->
		Dom.style Box: 'middle'
		Dom.h2 !->
			Dom.style Flex: 1
			Dom.text group.get(Page.state.get(2), 'name')
		group.iterate (activity) !->
			Ui.avatar Plugin.userAvatar(activity.get('userId')), undefined, undefined, !->
				Page.state.set 2, activity.key()

	Dom.div !->
		activity = group.ref(Page.state.get(2))
		Dom.div !->
			Dom.text tr("%1 km in %2 minutes averaging %3 km/h",
				round(activity.get('distance')*.001,2),
				round(activity.get('duration')/60),
				round(activity.get('distance')*3.6/activity.get('duration'),2))

	Social.renderComments path: [period, id]

obsFirst = (obs) ->
	# get .ref to first key
	for k,v of obs.peek()
		break
	if k
		r = obs.ref(k)
		r.n = k
		r

round = (int, precision=0) ->
	p = Math.pow(10,precision)
	Math.round(int*p)/p

exports.renderSettings = !->
	if Db.shared
		Ui.bigButton !->
			Dom.text tr("Refresh data")
			Dom.div !->
				Dom.style {fontSize: '70%', textAlign: 'center'}
				Dom.text "(done automatically once per hour)"
		, !->
			Server.call 'refresh'

curPeriod = ->
	d = new Date()
	d.getFullYear() + ('0'+(d.getMonth()+1)).substr(-2)

months = [tr("January"), tr("February"), tr("March"), tr("April"), tr("May"), tr("June"), tr("July"), tr("August"), tr("September"), tr("October"), tr("November"), tr("December")]

