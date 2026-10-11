'use strict';
'require view';
'require form';
'require uci';
'require fs';
'require ui';

function addIntervalValues(o) {
	o.value('900', _('15 minutes'));
	o.value('1800', _('30 minutes'));
	o.value('3600', _('1 hour'));
	o.value('21600', _('6 hours'));
	o.value('43200', _('12 hours'));
	o.value('86400', _('1 day'));
	o.value('259200', _('3 days'));
	o.value('604800', _('7 days'));
	o.editable = true;
	o.datatype = 'uinteger';
}

function addRetryValues(o) {
	o.value('60', _('1 minute'));
	o.value('300', _('5 minutes'));
	o.value('900', _('15 minutes'));
	o.value('1800', _('30 minutes'));
	o.value('3600', _('1 hour'));
	o.editable = true;
	o.datatype = 'uinteger';
}

function addCountrySuggestions(o) {
	[
		['RU', '🇷🇺 Russia'], ['US', '🇺🇸 United States'], ['DE', '🇩🇪 Germany'],
		['NL', '🇳🇱 Netherlands'], ['FI', '🇫🇮 Finland'], ['FR', '🇫🇷 France'],
		['GB', '🇬🇧 United Kingdom'], ['PL', '🇵🇱 Poland'], ['CZ', '🇨🇿 Czechia'],
		['AT', '🇦🇹 Austria'], ['CH', '🇨🇭 Switzerland'], ['SE', '🇸🇪 Sweden'],
		['NO', '🇳🇴 Norway'], ['DK', '🇩🇰 Denmark'], ['EE', '🇪🇪 Estonia'],
		['LV', '🇱🇻 Latvia'], ['LT', '🇱🇹 Lithuania'], ['UA', '🇺🇦 Ukraine'],
		['KZ', '🇰🇿 Kazakhstan'], ['AM', '🇦🇲 Armenia'], ['GE', '🇬🇪 Georgia'],
		['TR', '🇹🇷 Türkiye'], ['IL', '🇮🇱 Israel'], ['AE', '🇦🇪 UAE'],
		['SG', '🇸🇬 Singapore'], ['JP', '🇯🇵 Japan'], ['KR', '🇰🇷 South Korea'],
		['HK', '🇭🇰 Hong Kong'], ['TH', '🇹🇭 Thailand'], ['AU', '🇦🇺 Australia'],
		['CA', '🇨🇦 Canada']
	].forEach(function(c) {
		o.value(c[0], '%s (%s)'.format(c[1], c[0]));
	});
}

return view.extend({
	load: function() {
		return Promise.all([
			uci.load('podkop-sub-sync'),
			uci.load('podkop')
		]);
	},

	render: function() {
		var m, s, o;
		var podkopSections = uci.sections('podkop', 'section');
		var proxyTargets = {};
		var eligible = [];

		podkopSections.forEach(function(sec) {
			var name = sec['.name'];
			if ((sec.connection_type || '') === 'proxy') {
				proxyTargets[name] = sec;
				eligible.push(name);
			}
		});

		m = new form.Map('podkop-sub-sync', _('Podkop Subscription Sync'),
			_('One configuration file is used for all subscriptions. Each Podkop section is shown as a vertical block with all settings visible. The sync section name must match the Podkop section name. Eligible Podkop proxy sections: %s').format(eligible.length ? eligible.join(', ') : _('none')));

		s = m.section(form.TypedSection, 'sync', _('Podkop sections'));
		s.anonymous = false;
		s.addremove = true;
		s.addbtntitle = _('Add Podkop section');

		s.sectiontitle = function(section_id) {
			var p = proxyTargets[section_id];
			if (!p)
				return '%s — %s'.format(section_id, _('missing or not a proxy section'));

			return '%s — %s'.format(section_id, p.proxy_config_type || 'proxy');
		};

		s.renderSectionAdd = function(extra_class) {
			var el = form.TypedSection.prototype.renderSectionAdd.apply(this, arguments),
				nameEl = el.querySelector('.cbi-section-create-name');

			ui.addValidator(nameEl, 'uciname', true, function(v) {
				if (!proxyTargets[v])
					return _('Enter the name of an existing Podkop config section with connection_type=proxy. Available: %s').format(eligible.join(', '));

				if (uci.get('podkop-sub-sync', v))
					return _('A sync section named "%s" already exists.').format(v);

				return true;
			}, 'blur', 'keyup');

			nameEl.setAttribute('placeholder', eligible.length ? eligible.join(', ') : 'main');
			return el;
		};


		o = s.option(form.Flag, 'enabled', _('Enabled'));
		o.default = '0';
		o.rmempty = false;
		o.editable = true;

		o = s.option(form.DummyValue, '_podkop_section', _('Podkop section'));
		o.cfgvalue = function(section_id) {
			var p = proxyTargets[section_id];
			if (!p)
				return _('Not found / not proxy');
			return '%s (%s)'.format(section_id, p.proxy_config_type || 'proxy');
		};

		o = s.option(form.Value, 'url', _('Subscription URL'));
		o.password = true;
		o.rmempty = true;
		o.placeholder = 'https://example.com/sub/...';

		o = s.option(form.ListValue, 'interval', _('Sync interval'));
		addIntervalValues(o);
		o.default = '86400';
		o.rmempty = false;

		o = s.option(form.ListValue, 'retry_interval', _('Retry interval'));
		addRetryValues(o);
		o.default = '900';
		o.rmempty = false;

		o = s.option(form.Button, '_sync_now', _('Sync now'),
			_('Runs this Podkop section immediately. Save pending changes first.'));
		o.inputtitle = _('Run sync');
		o.inputstyle = 'apply';
		o.onclick = function(section_id) {
			return fs.exec('/usr/bin/podkop-sub-sync', [ section_id ]).then(function(res) {
				if (res.code === 0)
					ui.addNotification(null, E('p', {}, _('Subscription sync completed successfully.')), 'info');
				else if (res.code === 75)
					ui.addNotification(null, E('p', {}, _('Another subscription update is already running.')), 'warning');
				else
					ui.addNotification(null, E('p', {}, _('Subscription sync failed with code %s. Check the system log.').format(res.code)), 'error');
			});
		};

		o = s.option(form.Flag, 'enable_vless', _('VLESS'));
		o.default = '1';
		o.rmempty = false;

		o = s.option(form.Flag, 'enable_xhttp', _('XHTTP'));
		o.default = '0';
		o.rmempty = false;
		o.description = _('XHTTP is selectable independently from ordinary VLESS.');

		o = s.option(form.Flag, 'enable_trojan', _('Trojan'));
		o.default = '1';
		o.rmempty = false;

		o = s.option(form.Flag, 'enable_ss', _('Shadowsocks'));
		o.default = '1';
		o.rmempty = false;

		o = s.option(form.DynamicList, 'include_country', _('Include countries'),
			_('Whitelist. If non-empty, only these two-letter country codes are kept.'));
		addCountrySuggestions(o);
		o.datatype = 'list(string)';

		o = s.option(form.DynamicList, 'exclude_country', _('Exclude countries'),
			_('Blacklist applied after the include list.'));
		addCountrySuggestions(o);
		o.datatype = 'list(string)';

		o = s.option(form.Flag, 'precheck_enabled', _('Enable real proxy precheck'));
		o.default = '1';
		o.rmempty = false;

		o = s.option(form.Value, 'precheck_url', _('Test URL'));
		o.default = 'https://www.gstatic.com/generate_204';
		o.rmempty = false;
		o.depends('precheck_enabled', '1');

		o = s.option(form.ListValue, 'precheck_http_code', _('Expected HTTP code'));
		o.value('204', '204');
		o.value('200', '200');
		o.value('any', _('Any 2xx/3xx/4xx'));
		o.editable = true;
		o.default = '204';
		o.rmempty = false;
		o.depends('precheck_enabled', '1');

		o = s.option(form.Value, 'precheck_connect_timeout', _('Connect timeout (s)'));
		o.datatype = 'range(1,120)';
		o.default = '3';
		o.rmempty = false;
		o.depends('precheck_enabled', '1');

		o = s.option(form.Value, 'precheck_timeout', _('Total timeout (s)'));
		o.datatype = 'range(1,300)';
		o.default = '7';
		o.rmempty = false;
		o.depends('precheck_enabled', '1');

		o = s.option(form.Value, 'precheck_batch_size', _('Batch size'));
		o.datatype = 'range(1,64)';
		o.default = '6';
		o.rmempty = false;
		o.depends('precheck_enabled', '1');

		o = s.option(form.Value, 'precheck_base_port', _('Base test port'));
		o.datatype = 'port';
		o.default = '39000';
		o.rmempty = false;
		o.depends('precheck_enabled', '1');

		o = s.option(form.Value, 'precheck_min_nodes', _('Minimum working nodes'));
		o.datatype = 'uinteger';
		o.default = '3';
		o.rmempty = false;
		o.depends('precheck_enabled', '1');

		o = s.option(form.Value, 'precheck_min_percent', _('Minimum success (%)'));
		o.datatype = 'range(0,100)';
		o.default = '20';
		o.rmempty = false;
		o.depends('precheck_enabled', '1');

		o = s.option(form.Value, 'precheck_max_nodes', _('Keep fastest nodes'));
		o.datatype = 'uinteger';
		o.default = '20';
		o.rmempty = false;
		o.description = _('0 keeps all working nodes.');
		o.depends('precheck_enabled', '1');

		o = s.option(form.Flag, 'precheck_insecure_tls', _('Disable TLS verification'));
		o.default = '0';
		o.rmempty = false;
		o.depends('precheck_enabled', '1');

		o = s.option(form.Value, 'precheck_dns_server', _('Precheck DNS server'));
		o.datatype = 'ipaddr';
		o.placeholder = _('Podkop bootstrap DNS');
		o.rmempty = true;
		o.depends('precheck_enabled', '1');

		o = s.option(form.Flag, 'send_hwid', _('Send HWID headers'));
		o.default = '0';
		o.rmempty = false;

		o = s.option(form.Value, 'hwid', _('HWID override'));
		o.rmempty = true;
		o.depends('send_hwid', '1');

		o = s.option(form.Value, 'user_agent', _('HTTP User-Agent'));
		o.rmempty = true;
		o.placeholder = _('Automatic versioned default');

		return m.render();
	},

	handleSaveApply: function(ev, mode) {
		var restart = L.bind(function() {
			fs.exec('/etc/init.d/podkop-sub-sync', [ 'restart' ]);
			document.removeEventListener('uci-applied', restart);
		});

		document.addEventListener('uci-applied', restart);
		return this.super('handleSaveApply', [ ev, mode ]);
	}
});
