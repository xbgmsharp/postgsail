import { memo } from "react";
import { GlHero } from "gitlanding/GlHero/GlHero";
import { GlArticle } from "gitlanding/GlArticle";
import { GlCards } from "gitlanding/GlCards";
import { GlLogoCard } from "gitlanding/GlCards/GlLogoCard";
import { declareComponentKeys, useTranslation } from "i18n";
import heroPng from "assets/img/hero.png";
import articlePng from "assets/img/home-article.png";
import balloonIcon from "assets/icons/balloon.png";
import drawioIcon from "assets/icons/drawio.png";
import githubIcon from "assets/icons/github.png";
import plusIcon from "assets/icons/plus.png";
import rocketIcon from "assets/icons/rocket-chat.png";
import tchapIcon from "assets/icons/tchap.png";

export const Home = memo(() => {
	const { t } = useTranslation({ Home });
	return (
		<>
			<GlHero
				title={t("heroTitle")}
				subTitle={t("heroSubtitle")}
				illustration={{
					"type": "image",
					"src": heroPng,
					"hasShadow": false
				}}
				hasLinkToSectionBellow={true}
			/>

			<GlArticle
				title={t("articleTitle")}
				body={t("articleBody")}
				buttonLabel={t("articleButtonLabel")}
				buttonLink={{
					"href": "https://example.com",
				}}
				illustration={{
					"type": "image",
					"src": articlePng,
					"hasShadow": false
				}}
				hasAnimation={true}
				illustrationPosition="left"
			/>

			<GlCards>
				<GlLogoCard
					title={t("card1Title")}
					paragraph={t("card1Paragraph")}
					buttonLabel="Button Label"
					iconUrls={[
						tchapIcon,
						githubIcon

					]}
				/>
				<GlLogoCard
					title={t("card2Title")}
					paragraph={t("card2Paragraph")}
					buttonLabel="Button Label"
					iconUrls={[
						rocketIcon
					]}
				/>

				<GlLogoCard
					title={t("card3Title")}
					paragraph={t("card3Paragraph")}
					buttonLabel="Button Label"
					iconUrls={[
						balloonIcon,
						drawioIcon,
						rocketIcon,
						plusIcon
					]}
					overlapIcons={true}
				/>
			</GlCards>
		</>
	);
});

export const { i18n } = declareComponentKeys<
	| "heroTitle"
	| "heroSubtitle"
	| "articleTitle"
	| "articleBody"
	| "articleButtonLabel"
	| "card1Title"
	| "card2Title"
	| "card3Title"
	| "card1Paragraph"
	| "card2Paragraph"
	| "card3Paragraph"
>()({ Home });