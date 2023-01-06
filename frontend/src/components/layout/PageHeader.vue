<template lang="pug">
.flex.w-full
  .flex.cursor-pointer
    img(alt='logo', src='@/assets/logo.svg', width='35', height='35')
    p.ml-3.mt-2.text-2xl.text-white POCoin
  p.header-subtitle(style='margin-top: 0.54rem') |
  p.header-subtitle(style='margin-top: 0.64rem') A Blockchain visualization
</template>

<style scoped>
.header-subtitle {
  @apply font-thin text-xl text-white ml-3;
}
</style>
