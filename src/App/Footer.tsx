import { memo } from "react";
import { GlFooter } from "gitlanding/GlFooter";
//import { routes } from "router";
import { declareComponentKeys, useTranslation } from "i18n";


export const Footer = memo(() => {
	const { t } = useTranslation({ Footer })
	return <GlFooter
		bottomDivContent={t("license")}
		email="info@openplotter.cloud"
		phoneNumber="+33652584319"
		links={[
			{
				"label": t("link2label"),
				"href": "https://github.com/xbgmsharp/postgsail/",
			},
			{
				"label": t("link3label"),
				"href": "https://github.com/xbgmsharp/postgsail/blob/main/README.md",
			},
			{
				"label": "Support",
				"href": "https://discord.gg/cpGqA5sZ",
			},
		]}
	/>
})

export const { i18n } = declareComponentKeys<
	| "license"
	| "link1label"
	| "link2label"
	| "link3label"
>()({ Footer });
