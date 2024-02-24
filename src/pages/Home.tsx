import { memo } from "react";
import { GlHero } from "gitlanding/GlHero/GlHero";
import { GlArticle } from "gitlanding/GlArticle";
import { GlCards } from "gitlanding/GlCards";
import { GlLogoCard } from "gitlanding/GlCards/GlLogoCard";
import { declareComponentKeys, useTranslation } from "i18n";
/*
import heroPng from "assets/img/hero.png";
import articlePng from "assets/img/home-article.png";
import balloonIcon from "assets/icons/balloon.png";
import drawioIcon from "assets/icons/drawio.png";
import githubIcon from "assets/icons/github.png";
import plusIcon from "assets/icons/plus.png";
import rocketIcon from "assets/icons/rocket-chat.png";
import tchapIcon from "assets/icons/tchap.png";
*/
import githubIcon from "assets/icons/github.png";
import discordIcon from "assets/icons/discord-mark-blue.png";
import grafanaIcon from "assets/icons/Grafana_logo.png";

import { GlProjectCard } from "gitlanding/GlCards/GlProjectCard";
import { GlCheckList } from "gitlanding/GlCheckList";
import { GlSectionDivider } from "gitlanding/GlSectionDivider";
/*
import pokemonPng from "assets/img/pokemon.png";
import dataPng from "assets/img/data-visualisation.png";
import kubernetesPng from "assets/img/kubernetes.png";
import webinairePng from "assets/img/webinaire.png";
import demoGif from "assets/img/demo.gif";
*/
import timelapsePng from "assets/img/timelapse.png";
import monitoringPng from "assets/img/monitoring.png";
import logsPng from "assets/img/logs.png";
import mapPng from "assets/img/map.png";
import statsPng from "assets/img/stats.png";

export const Home = memo(() => {
	const { t } = useTranslation({ Home });
	return (
		<>
			<GlHero
				title={t("heroTitle")}
				subTitle={t("heroSubtitle")}
				/*illustration={{
					"type": "image",
					"src": demoGif,
					"hasShadow": false
				}}
				*/
				illustration={{
					"type": "video",
					"sources": [
					  {
						"src": "demo.mp4",
						"type": "video/mp4"
					  }
					]
				  }}
				hasLinkToSectionBellow={true}
				illustrationZoomFactor={1.3}
			/>


<GlArticle
			title={t("articleTitle")}
			body={t("articleBody")}
			buttonLabel={t("articleButtonLabel")}
			buttonLink={{
				"href": "https://iot.openplotter.cloud",
			}}
			illustration={{
				"type": "image",
				"src": timelapsePng,
				"hasShadow": true
			}}
			illustrationPosition='left'
			hasAnimation={true}
		/>

<GlArticle
			title={t("article2Title")}
			body={t("article2Body")}
			buttonLabel={t("articleButtonLabel")}
			buttonLink={{
				"href": "https://iot.openplotter.cloud",
			}}
			illustration={{
				"type": "image",
				"src": monitoringPng,
				"hasShadow": true
			}}
			hasAnimation={true}
		/>

<GlArticle
			title={t("article3Title")}
			body={t("article3Body")}
			buttonLabel={t("articleButtonLabel")}
			buttonLink={{
				"href": "https://iot.openplotter.cloud",
			}}
			illustration={{
				"type": "image",
				"src": logsPng,
				"hasShadow": true
			}}
			illustrationPosition='left'
			hasAnimation={true}
		/>

<GlSectionDivider />

		<GlCards>
			<GlProjectCard
				title={t("projectCardTitle1")}
				subtitle={t("projectCardSubtitle1")}
				projectImageUrl={timelapsePng}
			/>
			<GlProjectCard
				title={t("projectCardTitle2")}
				subtitle={t("projectCardSubtitle2")}
				projectImageUrl={logsPng}
			/>
			<GlProjectCard
				title={t("projectCardTitle3")}
				subtitle={t("projectCardSubtitle3")}
				projectImageUrl={monitoringPng}
			/>
			<GlProjectCard
				title={t("projectCardTitle4")}
				subtitle={t("projectCardSubtitle4")}
				projectImageUrl={statsPng}
			/>
		</GlCards>

		<GlSectionDivider />

		<GlCheckList
			heading={t("checkListHeading")}
			hasAnimation={true}
			elements={

				[
					{
						"title": t(`checkListElementTitle1`),
						"description": t("checkListElementDescription1")
					},
					{
						"title": t(`checkListElementTitle2`),
						"description": t("checkListElementDescription2")
					},
					{
						"title": t(`checkListElementTitle3`),
						"description": t("checkListElementDescription3")
					},
					{
						"title": t(`checkListElementTitle4`),
						"description": t("checkListElementDescription4")
					},
					{
						"title": t(`checkListElementTitle5`),
						"description": t("checkListElementDescription5")
					},
					{
						"title": t(`checkListElementTitle6`),
						"description": t("checkListElementDescription6")
					},
					{
						"title": t(`checkListElementTitle7`),
						"description": t("checkListElementDescription7")
					},
					{
						"title": t(`checkListElementTitle8`),
						"description": t("checkListElementDescription8")
					},
					{
						"title": t(`checkListElementTitle9`),
						"description": t("checkListElementDescription9")
					},
				]
			}
		/>

		<GlCards>
				<GlLogoCard
					title={t("card1Title")}
					paragraph={t("card1Paragraph")}
					buttonLabel="Code in GitHub"
					iconUrls={[
						githubIcon
					]}
					link={{
						"href": "https://github.com/xbgmsharp/postgsail/",
					}}
				/>
				<GlLogoCard
					title={t("card2Title")}
					paragraph={t("card2Paragraph")}
					buttonLabel="Community & Support"
					iconUrls={[
						discordIcon
					]}
					link={{
						"href": "https://discord.gg/cpGqA5sZ",
					}}
				/>

				<GlLogoCard
					title={t("card3Title")}
					paragraph={t("card3Paragraph")}
					buttonLabel="Make it yours"
					iconUrls={[
						grafanaIcon
					]}
					link={{
						"href": "https://iot.openplotter.cloud",
					}}
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
	| "articleTitle"
	| "articleBody"
	| "articleButtonLabel"
	| "article2Title"
	| "article2Body"
	| "article2ButtonLabel"
	| "article3Title"
	| "article3Body"
	| "article3ButtonLabel"
	| "projectCardTitle1"
	| "projectCardTitle2"
	| "projectCardTitle3"
	| "projectCardTitle4"
	| "projectCardSubtitle1"
	| "projectCardSubtitle2"
	| "projectCardSubtitle3"
	| "projectCardSubtitle4"
	| "checkListHeading"
	| "checkListElementTitle1"
	| "checkListElementTitle2"
	| "checkListElementTitle3"
	| "checkListElementTitle4"
	| "checkListElementTitle5"
	| "checkListElementTitle6"
	| "checkListElementTitle7"
	| "checkListElementTitle8"
	| "checkListElementTitle9"
	| "checkListElementDescription1"
	| "checkListElementDescription2"
	| "checkListElementDescription3"
	| "checkListElementDescription4"
	| "checkListElementDescription5"
	| "checkListElementDescription6"
	| "checkListElementDescription7"
	| "checkListElementDescription8"
	| "checkListElementDescription9"
>()({ Home });