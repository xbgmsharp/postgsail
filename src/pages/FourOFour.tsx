import { memo } from "react";
import { makeStyles, Text } from "theme";
import { declareComponentKeys } from "i18nifty";
import { useTranslation } from "i18n";

export const FourOhFour = memo(() => {
    const { classes } = useStyles();
    const { t } = useTranslation({ FourOhFour });

    return (
        <div className={classes.root}>
            <Text typo="page heading">{t("not found")} 😥</Text>
        </div>
    );
});

export const { i18n } = declareComponentKeys<"not found">()({
    FourOhFour,
});

const useStyles = makeStyles({ "name": { FourOhFour } })(theme => ({
    "root": {
        "display": "flex",
        "alignItems": "center",
        "justifyContent": "center",
        "backgroundColor": theme.colors.useCases.surfaces.background,
    },
}));