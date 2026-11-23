package com.openbitfun.mobile.app.ui.shell

import androidx.compose.animation.core.*
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.graphics.luminance
import androidx.compose.ui.draw.drawWithContent
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.compose.LocalLifecycleOwner
import androidx.lifecycle.repeatOnLifecycle
import com.openbitfun.mobile.app.R
import com.openbitfun.mobile.app.ui.miniapps.MiniAppsButton
import com.openbitfun.mobile.app.ui.theme.generated.MobileDesignColors
import com.openbitfun.mobile.app.ui.theme.generated.MobileDesignGeometry as G
import kotlinx.coroutines.currentCoroutineContext
import kotlinx.coroutines.awaitCancellation
import kotlin.math.*

/** A welcome layout, C text motion. Only presentation state is kept here. */
@Composable
internal fun WelcomeHome(
    onLogin: () -> Unit,
    onOpenSidebar: () -> Unit,
    signedIn: Boolean = false,
    modifier: Modifier = Modifier,
) {
    val ink = MaterialTheme.colorScheme.onBackground
    val light = MaterialTheme.colorScheme.background.luminance() > .5f
    val page = if (light) MobileDesignColors.Light.WelcomePageBg else MobileDesignColors.Dark.WelcomePageBg
    val dock = if (light) MobileDesignColors.Light.WelcomeDock else MobileDesignColors.Dark.WelcomeDock
    val bottomInset = WindowInsets.navigationBars.asPaddingValues().calculateBottomPadding()
    BoxWithConstraints(modifier.fillMaxSize().background(page).statusBarsPadding().displayCutoutPadding()) {
        val wide = maxWidth >= 600.dp
        val landscape = maxWidth >= 840.dp && maxWidth.value >= maxHeight.value * 1.2f
        val contentHeight = (maxHeight - G.WelcomeHeaderHeight).coerceAtLeast(0.dp)
        val markSize = when {
            landscape -> G.WelcomeLandscapeMarkSize
            wide -> G.WelcomeWideMarkSize
            else -> G.WelcomeMarkSize
        }
        val hero: @Composable () -> Unit = {
            Column(
                horizontalAlignment = Alignment.CenterHorizontally,
                verticalArrangement = Arrangement.spacedBy(if (wide) 16.dp else 20.dp),
                modifier = Modifier.fillMaxWidth().padding(bottom = if (wide) 32.dp else 0.dp),
            ) {
                WelcomeBrandFlow(Modifier.size(markSize), sweep = true)
                WelcomePhrase()
            }
        }
        val actions: @Composable () -> Unit = {
            Column(
                Modifier.widthIn(max = if (wide) G.WelcomeWideActionWidth else G.WelcomeMaxWidth).fillMaxWidth()
                    .background(if (wide) MobileDesignColors.Light.Transparent else dock, RoundedCornerShape(topStart = G.WelcomeDockRadius, topEnd = G.WelcomeDockRadius))
                    .padding(start = G.WelcomeGutter, end = G.WelcomeGutter,
                        top = if (wide) 0.dp else G.WelcomeGutter,
                        bottom = if (wide) 0.dp else maxOf(G.WelcomeDockBottom, bottomInset)),
                verticalArrangement = Arrangement.spacedBy(G.WelcomeButtonGap),
            ) {
                Button(
                    onLogin, Modifier.fillMaxWidth().height(G.WelcomeButtonHeight), shape = RoundedCornerShape(28.dp),
                    colors = ButtonDefaults.buttonColors(
                        containerColor = if (wide) ink else MobileDesignColors.Light.WelcomeButton,
                        contentColor = if (wide) MaterialTheme.colorScheme.background else MobileDesignColors.Light.WelcomeButtonLabel,
                    ),
                ) {
                    Text(
                        stringResource(if (signedIn) R.string.sidebar_connect_desktop else R.string.welcome_login),
                        style = MaterialTheme.typography.labelMedium, fontWeight = FontWeight.Medium,
                    )
                }
                MiniAppsButton(
                    explore = true,
                    contentColor = if (wide) MaterialTheme.colorScheme.onSurfaceVariant else MobileDesignColors.Light.WelcomeSecondary,
                )
            }
        }
        Column(Modifier.fillMaxWidth().verticalScroll(rememberScrollState()), horizontalAlignment = Alignment.CenterHorizontally) {
            Row(
                Modifier.fillMaxWidth().height(G.WelcomeHeaderHeight)
                    .padding(start = if (wide) 40.dp else G.WelcomeGutter, end = G.WelcomeGutter),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Row { "OpenBitFun".forEach { WelcomeGlyph(it, G.WelcomeHeaderWordSize.value, Modifier) } }
                Spacer(Modifier.weight(1f))
                WelcomeSidebarButton(onOpenSidebar)
            }
            when {
                landscape -> Row(
                    Modifier.widthIn(max = G.WelcomeLandscapeWidth).fillMaxWidth()
                        .heightIn(min = maxOf(400.dp, contentHeight)).padding(start = 40.dp, end = 40.dp, bottom = 48.dp),
                    horizontalArrangement = Arrangement.spacedBy(48.dp), verticalAlignment = Alignment.CenterVertically,
                ) {
                    Box(Modifier.weight(1f), contentAlignment = Alignment.Center) { hero() }
                    Box(Modifier.weight(1f), contentAlignment = Alignment.Center) { actions() }
                }
                wide -> Column(
                    Modifier.fillMaxWidth().heightIn(min = maxOf(540.dp, contentHeight)).padding(bottom = 64.dp),
                    horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.Center,
                ) {
                    hero()
                    actions()
                }
                else -> Column(Modifier.fillMaxWidth().height(maxOf(430.dp, contentHeight))) {
                    Box(Modifier.fillMaxWidth().weight(1f).padding(bottom = 24.dp), contentAlignment = Alignment.Center) { hero() }
                    actions()
                }
            }
        }
    }
}

@Composable
private fun WelcomeSidebarButton(onClick: () -> Unit) {
    val tint = MaterialTheme.colorScheme.onSurfaceVariant
    val description = stringResource(R.string.welcome_open_sidebar)
    IconButton(onClick, Modifier.size(G.ControlTouchSize).semantics { contentDescription = description }) {
        Box(Modifier.size(22.dp, 20.dp).border(1.5.dp, tint, RoundedCornerShape(4.dp)).padding(3.dp)) {
            Row(Modifier.fillMaxHeight().width(7.dp)) {
                Box(Modifier.fillMaxHeight().width(6.dp).background(tint.copy(alpha = .18f)))
                VerticalDivider(color = tint.copy(alpha = .7f))
            }
        }
    }
}

@Composable
internal fun WelcomePhrase(
    wordSize: androidx.compose.ui.unit.Dp = G.WelcomeWordSize,
    longWordSize: androidx.compose.ui.unit.Dp = G.WelcomeLongWordSize,
    stageHeight: androidx.compose.ui.unit.Dp = G.WelcomeStageHeight,
) {
    val phrases = listOf("OpenBitFun", stringResource(R.string.welcome_work), stringResource(R.string.welcome_play), stringResource(R.string.welcome_yours))
    var moving by remember { mutableStateOf(false) }
    val lifecycle = LocalLifecycleOwner.current.lifecycle
    LaunchedEffect(lifecycle) {
        lifecycle.repeatOnLifecycle(Lifecycle.State.RESUMED) {
            moving = currentCoroutineContext()[androidx.compose.ui.MotionDurationScale]?.scaleFactor != 0f
            try { awaitCancellation() } finally { moving = false }
        }
    }
    val duration = phrases.sumOf { welcomeDuration(it) }
    val elapsed = if (moving) rememberInfiniteTransition(label = "welcome-copy").animateFloat(
        initialValue = 0f, targetValue = duration.toFloat(),
        animationSpec = infiniteRepeatable(tween(duration, easing = LinearEasing), RepeatMode.Restart),
        label = "welcome-time",
    ) else remember { mutableFloatStateOf(2700f) }
    var time = elapsed.value
    var phrase = phrases.first()
    for (item in phrases) { phrase = item; if (time < welcomeDuration(item)) break; time -= welcomeDuration(item) }

    Row(
        Modifier.height(stageHeight).clearAndSetSemantics { contentDescription = phrase },
        verticalAlignment = Alignment.CenterVertically,
    ) {
        phrase.forEachIndexed { index, letter ->
            val progress = ((time - 180 - index * 55) / 800).coerceIn(0f, 1f)
            val ease = 1 - (1 - progress).pow(3)
            val bump = sin(progress * PI).toFloat() * (1 - progress)
            val exit = ((time - welcomeDuration(phrase) + 650) / 650).coerceIn(0f, 1f)
            WelcomeGlyph(letter, if (phrase.length > 12) longWordSize.value else wordSize.value,
                Modifier.graphicsLayer {
                    alpha = (progress * 3).coerceIn(0f, 1f) * (1 - exit)
                    translationX = ((1 - ease) * 38 - bump * 5 - exit * exit * 30).dp.toPx()
                    scaleX = 1 + bump * .045f
                    scaleY = scaleX
                })
        }
    }
}

private fun welcomeDuration(word: String) = 250+word.length*185+(if(word=="OpenBitFun")600 else 0)+1800+650

@Composable
private fun WelcomeGlyph(letter: Char, fontSize: Float, modifier: Modifier) {
    Text(if(letter=='i') "ı" else letter.toString(), fontSize = fontSize.sp,
        fontWeight = FontWeight.Medium, color = MaterialTheme.colorScheme.onBackground,
        modifier = modifier.drawWithContent {
            drawContent()
            if(letter=='i') drawCircle(MobileDesignColors.Light.BrandDot, radius = fontSize.sp.toPx()*.07f,
                center = Offset(size.width/2, fontSize.sp.toPx()*.25f))
        })
}
