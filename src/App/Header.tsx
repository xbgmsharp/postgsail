import { memo } from "react";
import { GlHeader } from "gitlanding/GlHeader";
import { routes } from "router";
import { declareComponentKeys, useTranslation, useLang } from "i18n";
import { createLanguageSelect } from "onyxia-ui/LanguageSelect";
import type { Language } from "i18n";

const { LanguageSelect } = createLanguageSelect<Language>({
	"languagesPrettyPrint": {
		"en": "English",
		"fr": "Francais"
	}
})

export const Header = memo(() => {
	const { t } = useTranslation({ Header })
	const { lang, setLang } = useLang();
	return <GlHeader
		title={<a {...routes.home().link}><h1>{t("headerTitle")}</h1></a>}
		links={[
			{
				"label": t("link1label"),
				...routes.pageExample().link
			},
			{
				"label": t("link2label"),
				"href": "https://example.com",
			},
			{
				"label": t("link3label"),
				"href": "https://example.com",
			},
		]}
		enableDarkModeSwitch={true}
		githubRepoUrl="https://github.com/torvalds/linux"
		githubButtonSize="large"
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
