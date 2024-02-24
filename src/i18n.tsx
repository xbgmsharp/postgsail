import { createI18nApi, declareComponentKeys } from "i18nifty";
export { declareComponentKeys };

//List the languages you with to support
export const languages = ["en", "fr", "es"] as const;

//If the user's browser language doesn't match any 
//of the languages above specify the language to fallback to:  
export const fallbackLanguage = "en";

export type Language = typeof languages[number];

export type LocalizedString = Parameters<typeof resolveLocalizedString>[0];

export const { 
	useTranslation, 
	resolveLocalizedString, 
	useLang, 
	$lang,
	useResolveLocalizedString,
	/** For use outside of React */
	getTranslation 
} = createI18nApi<
    | typeof import ("pages/Home").i18n
    | typeof import ("pages/PageExample").i18n
    | typeof import ("App/Header").i18n
		| typeof import ("App/Footer").i18n
		| typeof import ("pages/FourOFour").i18n
>()(
    { languages, fallbackLanguage },
    {
        "en": {
					"FourOhFour": {
						"not found": "Page not found"
					},
					"Header": {
						"headerTitle": "PostgSail",
						"link1label": "Example page",
						"link2label": "GitHub",
						"link3label": "Documentation"
					},
					"Footer": {
						"license": "License Apache",
						"link1label": "Example page",
						"link2label": "GitHub",
						"link3label": "Documentation"
					},
					"Home": {
						"heroTitle": "Cloud, hosted and fully–managed, designed for all your needs.",
						"heroSubtitle": " Effortless cloud based solution for storing and sharing your SignalK data. Allow to effortlessly log your sails and monitor your boat with historical data.",
						"articleButtonLabel": "Try PostgSail for free now",
						"card1Title": "Open Source",
						"card2Title": "Join the community",
						"card3Title": "Customize",
						"card1Paragraph": `Source code is available on Github.`,
						"card2Paragraph": `Get support and exchange on Discord.`,
						"card3Paragraph": `Create and manage your own dashboards.`,
						"articleTitle": "Timelapse",
						"articleBody": `- See your real-time or historical track(s) via animated timelapse

- Select one voyage or a date range of multiple trips to animate

- Sharable! Keep tracks private or share with friends
						`,
						"article2Title": "Boat Monitoring",
						"article2Body": `- Check your vessel from anywhere in the world in real-time.

- Monitor windspeed, depth, baromteter, temperatures and more

- See historical (up-to 7 days) data

- View power and battery status

- Get automated push or email alerts for significant changes in status or location changes`,
						"article2ButtonLabel": "Article button label",
						"article3Title": "Automated Logging",
						"article3Body": `- Automatic. No app to start or button to push.

- Auto-identifies and names your start and stop positions

- Records duration, distance, average and max boat and wind speeds

- Add your own voyage notes or details in text box

- Upon voyage completion, PostgSail will automatically email your trip log and add it to your stats.`,
						"article3ButtonLabel": "Article button label",
						"projectCardTitle1": "ROUTE SHARING",
						"projectCardTitle2": "AUTO logging",
						"projectCardTitle3": "boat monitoring",
						"projectCardTitle4": "STATS & Maps",
						"projectCardSubtitle1": "Want to share your real-time location and data with your friends and family? Its easy to toggle on and share a private link with your track and current location mapped & historical track, boat and wind speeds.",
						"projectCardSubtitle2": "Never start (or forget to) start your tracking app again. PostgSail knows when you leave the dock and starts to log your trip automatically. Stats include location names, duration, speed, distance, wind and more. ",
						"projectCardSubtitle3": "Check in on your vessel from anywhere in the world in real-time. Reporting includes temperatures, depth, wind, humidity, location, voltage and many more options if your boat is sensor equipped. ",
						"projectCardSubtitle4": "See all your voyages in a single shot or map. Filter by date, type of moorages and more to see some incredible stats!",
						"checkListHeading": "Amazing features, all automated",
						"checkListElementTitle1": "Timelapse",
						"checkListElementTitle2": "Boat Monitoring",
						"checkListElementTitle3": "Automated Logging",
						"checkListElementTitle4": "Realtime Route Sharing",
						"checkListElementTitle5": "Stats and Maps",
						"checkListElementTitle6": "AI/ML",
						"checkListElementTitle7": "Telegram bot",
						"checkListElementTitle8": "Export",
						"checkListElementTitle9": "Polar performance",
						"checkListElementDescription1": "Timelapse your track. Replay your trips on a interactive map with all weather condition.",
						"checkListElementDescription2": "Monitor your boat.",
						"checkListElementDescription3": "Log your trips.",
						"checkListElementDescription4": "Go social",
						"checkListElementDescription5": "Track your stats. Awesome statistics and graphs.",
						"checkListElementDescription6": "Predictive failure.",
						"checkListElementDescription7": "Control your boat remotely.",
						"checkListElementDescription8": "Export to CSV, GPX, GeoJSON, KML and download your logs.",
						"checkListElementDescription9": "Generate performance information based on a polar diagram.",
					},
					"PageExample": {
						"articleTitle": "Article title",
						"articleBody": `Am finished rejoiced drawings so he 
							elegance. Set lose dear upon had two its what seen. 
							Held she sir how know what such whom. 
							Esteem put uneasy set piqued son depend her others. 
							Two dear held mrs feet view her old fine. Bore can 
							led than how has rank. Discovery any extensive has 
							commanded direction. Short at front which blind as. 
							Ye as procuring unwilling principle by.`,
						"articleButtonLabel": "Article button label",
						"article2Title": "Article title",
						"article2Body": `Am finished rejoiced drawings so he 
							elegance. Set lose dear upon had two its what seen. 
							Held she sir how know what such whom. 
							Esteem put uneasy set piqued son depend her others. 
							Two dear held mrs feet view her old fine. Bore can 
							led than how has rank. Discovery any extensive has 
							commanded direction. Short at front which blind as. 
							Ye as procuring unwilling principle by.`,
						"article2ButtonLabel": "Article button label",
						"article3Title": "Article title",
						"article3Body": `Am finished rejoiced drawings so he 
							elegance. Set lose dear upon had two its what seen. 
							Held she sir how know what such whom. 
							Esteem put uneasy set piqued son depend her others. 
							Two dear held mrs feet view her old fine. Bore can 
							led than how has rank. Discovery any extensive has 
							commanded direction. Short at front which blind as. 
							Ye as procuring unwilling principle by.`,
						"article3ButtonLabel": "Article button label",
						"projectCardTitle1": "ROUTE SHARING",
						"projectCardTitle2": "AUTO logging",
						"projectCardTitle3": "boat monitoring",
						"projectCardTitle4": "STATS & Maps",
						"projectCardSubtitle1": "Want to share your real-time location and data with your friends and family? Its easy to toggle on and share a private link with your track and current location mapped & historical track, boat and wind speeds.",
						"projectCardSubtitle2": "Never start (or forget to) start your tracking app again. PostgSail knows when you leave the dock and starts to log your trip automatically. Stats include location names, duration, speed, distance, wind and more. ",
						"projectCardSubtitle3": "Check in on your vessel from anywhere in the world in real-time. Reporting includes temperatures, depth, wind, humidity, location, voltage and many more options if your boat is sensor equipped. ",
						"projectCardSubtitle4": "See all your voyages in a single shot or map. Filter by date, type of moorages and more to see some incredible stats!",
						"checkListHeading": "Features",
						"checkListElementTitle1": "Timelapse",
						"checkListElementTitle2": "Boat Monitoring",
						"checkListElementTitle3": "Automated Logging",
						"checkListElementTitle4": "Realtime Route Sharing",
						"checkListElementTitle5": "Stats and Maps",
						"checkListElementTitle6": "AI/ML",
						"checkListElementDescription1": "Timelapse your track. Replay your trips on a interactive map with all weather condition.",
						"checkListElementDescription2": "Monitor your boat.",
						"checkListElementDescription3": "Log your trips.",
						"checkListElementDescription4": "Go social",
						"checkListElementDescription5": "Track your stats.",
						"checkListElementDescription6": "Predictive failure.",
					}
        },
		/* spell-checker: disable */
		"fr": {
			"FourOhFour": {
				"not found": "Page non trouvée"
			},
			"Header": {
				"headerTitle": "PostgSail",
				"link1label": "Exemple de page",
				"link2label": "Lien 2",
				"link3label": "Lien 3"
			},
			"Footer": {
				"license": "License Apache",
				"link1label": "Exemple de page",
				"link2label": "Lien 2",
				"link3label": "Lien 3"
			},
			"Home": {
				"heroTitle": "Cloud, hosted and fully–managed, designed for all your needs.",
				"heroSubtitle": " Effortless cloud based solution for storing and sharing your SignalK data. Allow to effortlessly log your sails and monitor your boat with historical data.",
				"articleButtonLabel": "Try PostgSail for free now",
				"card1Title": "Open Source",
				"card2Title": "Join the community",
				"card3Title": "Customize",
				"card1Paragraph": `Source code is available on Github`,
				"card2Paragraph": `Get support and exchange on Discord`,
				"card3Paragraph": `Make your own dashboard`,
				"articleTitle": "Timelapse",
				"articleBody": `- See your real-time or historical track(s) via animated timelapse

- Select one voyage or a date range of multiple trips to animate

- Sharable! Keep tracks private or share with friends
				`,
				"article2Title": "Boat Monitoring",
				"article2Body": `- Check your vessel from anywhere in the world in real-time.

- Monitor windspeed, depth, baromteter, temperatures and more

- See historical (up-to 7 days) data

- View power and battery status

- Get automated push or email alerts for significant changes in status or location changes`,
				"article2ButtonLabel": "Article button label",
				"article3Title": "Automated Logging",
				"article3Body": `- Automatic. No app to start or button to push.

- Auto-identifies and names your start and stop positions

- Records duration, distance, average and max boat and wind speeds

- Add your own voyage notes or details in text box

- Upon voyage completion, PostgSail will automatically email your trip log and add it to your stats.`,
				"article3ButtonLabel": "Article button label",
				"projectCardTitle1": "ROUTE SHARING",
				"projectCardTitle2": "AUTO logging",
				"projectCardTitle3": "boat monitoring",
				"projectCardTitle4": "STATS & Maps",
				"projectCardSubtitle1": "Want to share your real-time location and data with your friends and family? Its easy to toggle on and share a private link with your track and current location mapped & historical track, boat and wind speeds.",
				"projectCardSubtitle2": "Never start (or forget to) start your tracking app again. PostgSail knows when you leave the dock and starts to log your trip automatically. Stats include location names, duration, speed, distance, wind and more. ",
				"projectCardSubtitle3": "Check in on your vessel from anywhere in the world in real-time. Reporting includes temperatures, depth, wind, humidity, location, voltage and many more options if your boat is sensor equipped. ",
				"projectCardSubtitle4": "See all your voyages in a single shot or map. Filter by date, type of moorages and more to see some incredible stats!",
				"checkListHeading": "Amazing features, all automated",
				"checkListElementTitle1": "Timelapse",
				"checkListElementTitle2": "Boat Monitoring",
				"checkListElementTitle3": "Automated Logging",
				"checkListElementTitle4": "Realtime Route Sharing",
				"checkListElementTitle5": "Stats and Maps",
				"checkListElementTitle6": "AI/ML",
				"checkListElementTitle7": "Telegram bot",
				"checkListElementTitle8": "Stats and Maps",
				"checkListElementTitle9": "Polar performance",
				"checkListElementDescription1": "Timelapse your track. Replay your trips on a interactive map with all weather condition.",
				"checkListElementDescription2": "Monitor your boat.",
				"checkListElementDescription3": "Log your trips.",
				"checkListElementDescription4": "Go social",
				"checkListElementDescription5": "Track your stats.",
				"checkListElementDescription6": "Predictive failure.",
				"checkListElementDescription7": "Control your boat remotely.",
				"checkListElementDescription8": "Track your stats.",
				"checkListElementDescription9": "Generate performance information based on a polar diagram.",	
			},
			"PageExample": {
				"articleTitle": "Article title",
				"articleBody": `Am finished rejoiced drawings so he 
					elegance. Set lose dear upon had two its what seen. 
					Held she sir how know what such whom. 
					Esteem put uneasy set piqued son depend her others. 
					Two dear held mrs feet view her old fine. Bore can 
					led than how has rank. Discovery any extensive has 
					commanded direction. Short at front which blind as. 
					Ye as procuring unwilling principle by.`,
				"articleButtonLabel": "Article button label",
				"article2Title": "Article title",
				"article2Body": `Am finished rejoiced drawings so he 
					elegance. Set lose dear upon had two its what seen. 
					Held she sir how know what such whom. 
					Esteem put uneasy set piqued son depend her others. 
					Two dear held mrs feet view her old fine. Bore can 
					led than how has rank. Discovery any extensive has 
					commanded direction. Short at front which blind as. 
					Ye as procuring unwilling principle by.`,
				"article2ButtonLabel": "Article button label",
				"article3Title": "Article title",
				"article3Body": `Am finished rejoiced drawings so he 
					elegance. Set lose dear upon had two its what seen. 
					Held she sir how know what such whom. 
					Esteem put uneasy set piqued son depend her others. 
					Two dear held mrs feet view her old fine. Bore can 
					led than how has rank. Discovery any extensive has 
					commanded direction. Short at front which blind as. 
					Ye as procuring unwilling principle by.`,
				"article3ButtonLabel": "Article button label",
				"projectCardTitle1": "ROUTE SHARING",
				"projectCardTitle2": "AUTO logging",
				"projectCardTitle3": "boat monitoring",
				"projectCardTitle4": "STATS & Maps",
				"projectCardSubtitle1": "Want to share your real-time location and data with your friends and family? Its easy to toggle on and share a private link with your track and current location mapped & historical track, boat and wind speeds.",
				"projectCardSubtitle2": "Never start (or forget to) start your tracking app again. PostgSail knows when you leave the dock and starts to log your trip automatically. Stats include location names, duration, speed, distance, wind and more. ",
				"projectCardSubtitle3": "Check in on your vessel from anywhere in the world in real-time. Reporting includes temperatures, depth, wind, humidity, location, voltage and many more options if your boat is sensor equipped. ",
				"projectCardSubtitle4": "See all your voyages in a single shot or map. Filter by date, type of moorages and more to see some incredible stats!",
				"checkListHeading": "Features",
				"checkListElementTitle1": "Timelapse",
				"checkListElementTitle2": "Boat Monitoring",
				"checkListElementTitle3": "Automated Logging",
				"checkListElementTitle4": "Realtime Route Sharing",
				"checkListElementTitle5": "Stats and Maps",
				"checkListElementTitle6": "AI/ML",
				"checkListElementDescription1": "Timelapse your track. Replay your trips on a interactive map with all weather condition.",
				"checkListElementDescription2": "Monitor your boat.",
				"checkListElementDescription3": "Log your trips.",
				"checkListElementDescription4": "Go social",
				"checkListElementDescription5": "Track your stats.",
				"checkListElementDescription6": "Predictive failure.",		}
		},
		/* spell-checker: disable */
		"es": {
			"FourOhFour": {
				"not found": "Page non trouvée"
			},
			"Header": {
				"headerTitle": "PostgSail",
				"link1label": "Exemple de page",
				"link2label": "Lien 2",
				"link3label": "Lien 3"
			},
			"Footer": {
				"license": "License Apache",
				"link1label": "Exemple de page",
				"link2label": "Lien 2",
				"link3label": "Lien 3"
			},
			"Home": {
				"heroTitle": "Cloud, hosted and fully–managed, designed for all your needs.",
				"heroSubtitle": " Effortless cloud based solution for storing and sharing your SignalK data. Allow to effortlessly log your sails and monitor your boat with historical data.",
				"articleButtonLabel": "Try PostgSail for free now",
				"card1Title": "Open Source",
				"card2Title": "Join the community",
				"card3Title": "Customize",
				"card1Paragraph": `Source code is available on Github`,
				"card2Paragraph": `Get support and exchange on Discord`,
				"card3Paragraph": `Make your own dashboard`,
				"articleTitle": "Timelapse",
				"articleBody": `- See your real-time or historical track(s) via animated timelapse

- Select one voyage or a date range of multiple trips to animate

- Sharable! Keep tracks private or share with friends
				`,
				"article2Title": "Boat Monitoring",
				"article2Body": `- Check your vessel from anywhere in the world in real-time.

- Monitor windspeed, depth, baromteter, temperatures and more

- See historical (up-to 7 days) data

- View power and battery status

- Get automated push or email alerts for significant changes in status or location changes`,
				"article2ButtonLabel": "Article button label",
				"article3Title": "Automated Logging",
				"article3Body": `- Automatic. No app to start or button to push.

- Auto-identifies and names your start and stop positions

- Records duration, distance, average and max boat and wind speeds

- Add your own voyage notes or details in text box

- Upon voyage completion, PostgSail will automatically email your trip log and add it to your stats.`,
				"article3ButtonLabel": "Article button label",
				"projectCardTitle1": "ROUTE SHARING",
				"projectCardTitle2": "AUTO logging",
				"projectCardTitle3": "boat monitoring",
				"projectCardTitle4": "STATS & Maps",
				"projectCardSubtitle1": "Want to share your real-time location and data with your friends and family? Its easy to toggle on and share a private link with your track and current location mapped & historical track, boat and wind speeds.",
				"projectCardSubtitle2": "Never start (or forget to) start your tracking app again. PostgSail knows when you leave the dock and starts to log your trip automatically. Stats include location names, duration, speed, distance, wind and more. ",
				"projectCardSubtitle3": "Check in on your vessel from anywhere in the world in real-time. Reporting includes temperatures, depth, wind, humidity, location, voltage and many more options if your boat is sensor equipped. ",
				"projectCardSubtitle4": "See all your voyages in a single shot or map. Filter by date, type of moorages and more to see some incredible stats!",
				"checkListHeading": "Amazing features, all automated",
				"checkListElementTitle1": "Timelapse",
				"checkListElementTitle2": "Boat Monitoring",
				"checkListElementTitle3": "Automated Logging",
				"checkListElementTitle4": "Realtime Route Sharing",
				"checkListElementTitle5": "Stats and Maps",
				"checkListElementTitle6": "AI/ML",
				"checkListElementTitle7": "Telegram bot",
				"checkListElementTitle8": "Stats and Maps",
				"checkListElementTitle9": "Polar performance",
				"checkListElementDescription1": "Timelapse your track. Replay your trips on a interactive map with all weather condition.",
				"checkListElementDescription2": "Monitor your boat.",
				"checkListElementDescription3": "Log your trips.",
				"checkListElementDescription4": "Go social",
				"checkListElementDescription5": "Track your stats.",
				"checkListElementDescription6": "Predictive failure.",
				"checkListElementDescription7": "Control your boat remotely.",
				"checkListElementDescription8": "Track your stats.",
				"checkListElementDescription9": "Generate performance information based on a polar diagram.",	
			},
			"PageExample": {
				"articleTitle": "Article title",
				"articleBody": `Am finished rejoiced drawings so he 
					elegance. Set lose dear upon had two its what seen. 
					Held she sir how know what such whom. 
					Esteem put uneasy set piqued son depend her others. 
					Two dear held mrs feet view her old fine. Bore can 
					led than how has rank. Discovery any extensive has 
					commanded direction. Short at front which blind as. 
					Ye as procuring unwilling principle by.`,
				"articleButtonLabel": "Article button label",
				"article2Title": "Article title",
				"article2Body": `Am finished rejoiced drawings so he 
					elegance. Set lose dear upon had two its what seen. 
					Held she sir how know what such whom. 
					Esteem put uneasy set piqued son depend her others. 
					Two dear held mrs feet view her old fine. Bore can 
					led than how has rank. Discovery any extensive has 
					commanded direction. Short at front which blind as. 
					Ye as procuring unwilling principle by.`,
				"article2ButtonLabel": "Article button label",
				"article3Title": "Article title",
				"article3Body": `Am finished rejoiced drawings so he 
					elegance. Set lose dear upon had two its what seen. 
					Held she sir how know what such whom. 
					Esteem put uneasy set piqued son depend her others. 
					Two dear held mrs feet view her old fine. Bore can 
					led than how has rank. Discovery any extensive has 
					commanded direction. Short at front which blind as. 
					Ye as procuring unwilling principle by.`,
				"article3ButtonLabel": "Article button label",
				"projectCardTitle1": "ROUTE SHARING",
				"projectCardTitle2": "AUTO logging",
				"projectCardTitle3": "boat monitoring",
				"projectCardTitle4": "STATS & Maps",
				"projectCardSubtitle1": "Want to share your real-time location and data with your friends and family? Its easy to toggle on and share a private link with your track and current location mapped & historical track, boat and wind speeds.",
				"projectCardSubtitle2": "Never start (or forget to) start your tracking app again. PostgSail knows when you leave the dock and starts to log your trip automatically. Stats include location names, duration, speed, distance, wind and more. ",
				"projectCardSubtitle3": "Check in on your vessel from anywhere in the world in real-time. Reporting includes temperatures, depth, wind, humidity, location, voltage and many more options if your boat is sensor equipped. ",
				"projectCardSubtitle4": "See all your voyages in a single shot or map. Filter by date, type of moorages and more to see some incredible stats!",
				"checkListHeading": "Features",
				"checkListElementTitle1": "Timelapse",
				"checkListElementTitle2": "Boat Monitoring",
				"checkListElementTitle3": "Automated Logging",
				"checkListElementTitle4": "Realtime Route Sharing",
				"checkListElementTitle5": "Stats and Maps",
				"checkListElementTitle6": "Predictive failure",
				"checkListElementDescription1": "Il remarquait et en survivants eclaireurs legerement qu. Animaux nos humains fer fut ramassa encourt.",
				"checkListElementDescription2": "Il remarquait et en survivants eclaireurs legerement qu. Animaux nos humains fer fut ramassa encourt.",
				"checkListElementDescription3": "Il remarquait et en survivants eclaireurs legerement qu. Animaux nos humains fer fut ramassa encourt.",
				"checkListElementDescription4": "Il remarquait et en survivants eclaireurs legerement qu. Animaux nos humains fer fut ramassa encourt.",
				"checkListElementDescription5": "Il remarquait et en survivants eclaireurs legerement qu. Animaux nos humains fer fut ramassa encourt.",
				"checkListElementDescription6": "Il remarquait et en survivants eclaireurs legerement qu. Animaux nos humains fer fut ramassa encourt.",
			}

		}
		/* spell-checker: enabled */
    }
);