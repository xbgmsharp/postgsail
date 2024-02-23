import { memo } from "react";
import { GlArticle } from "gitlanding/GlArticle";
import { GlProjectCard } from "gitlanding/GlCards/GlProjectCard";
import { GlCheckList } from "gitlanding/GlCheckList";
import { GlCards } from "gitlanding/GlCards";
import { GlSectionDivider } from "gitlanding/GlSectionDivider";
import { declareComponentKeys, useTranslation } from "i18n";
import articlePng from "assets/img/article-page-example.png"
import pokemonPng from "assets/img/pokemon.png";
import dataPng from "assets/img/data-visualisation.png";
import kubernetesPng from "assets/img/kubernetes.png";
import webinairePng from "assets/img/webinaire.png";


export const PageExample = memo(() => {

	const { t } = useTranslation({ PageExample })

	return <>

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
		/>

		<GlCards>
			<GlProjectCard
				title={t("projectCardTitle1")}
				subtitle={t("projectCardSubtitle1")}
				projectImageUrl={pokemonPng}
			/>
			<GlProjectCard
				title={t("projectCardTitle2")}
				subtitle={t("projectCardSubtitle2")}
				projectImageUrl={dataPng}
			/>
			<GlProjectCard
				title={t("projectCardTitle3")}
				subtitle={t("projectCardSubtitle3")}
				projectImageUrl={kubernetesPng}
			/>
			<GlProjectCard
				title={t("projectCardTitle4")}
				subtitle={t("projectCardSubtitle4")}
				projectImageUrl={webinairePng}
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
				]
			}
		/>

	</>
});

export const { i18n } = declareComponentKeys<
	| "articleTitle"
	| "articleBody"
	| "articleButtonLabel"
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
	| "checkListElementDescription1"
	| "checkListElementDescription2"
	| "checkListElementDescription3"
	| "checkListElementDescription4"
	| "checkListElementDescription5"
	| "checkListElementDescription6"
>()({ PageExample })