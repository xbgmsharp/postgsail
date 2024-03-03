import { memo } from "react";
import { GlHeader } from "gitlanding/GlHeader";
import { routes } from "router";
import { declareComponentKeys, useTranslation, useLang } from "i18n";
import { createLanguageSelect } from "onyxia-ui/LanguageSelect";
import type { Language } from "i18n";
import PostgsailLogo from "assets/PostgsailLogo.svg"

const { LanguageSelect } = createLanguageSelect<Language>({
	"languagesPrettyPrint": {
		"en": "English",
		"fr": "Francais",
		"es": "Spanish"
	}
})

export const Header = memo(() => {
	const { t } = useTranslation({ Header })
	const { lang, setLang } = useLang();
	return <GlHeader
		title={<a {...routes.home().link}><h1><img src={PostgsailLogo} alt="Postgsail Logo" height={48}/></h1></a>}
		links={[
			{
				"label": t("link2label"),
				"href": "https://github.com/xbgmsharp/postgsail/",
			},
			{
				"label": t("link3label"),
				"href": "https://github.com/xbgmsharp/postgsail/blob/main/README.md",
			},
		]}
		enableDarkModeSwitch={true}
		githubRepoUrl="https://github.com/xbgmsharp/postgsail/"
		githubButtonSize="large"
		showGithubStarCount={true}
		customItemEnd={{
			"item": <LanguageSelect
				language={lang}
				onLanguageChange={setLang}
				variant="big"
			/>
		}}

	/>
});

export const { i18n } = declareComponentKeys<
	| "headerTitle"
	| "link1label"
	| "link2label"
	| "link3label"
>()({ Header });
