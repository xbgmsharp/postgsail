import { createMakeStyles } from "tss-react";
import { createThemeProvider, defaultGetTypographyDesc } from "onyxia-ui";
import { createText } from "onyxia-ui/Text";


export const { useTheme, ThemeProvider } = createThemeProvider({
	"getTypographyDesc": params => ({
		...defaultGetTypographyDesc(params),
		"fontFamily": '"Open Sans", sans-serif'
	})
});

export const { makeStyles } = createMakeStyles({ useTheme });
export const { Text } = createText({ useTheme });